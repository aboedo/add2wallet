"""Apple Wallet Pass Generator Service."""

import json
import os
import tempfile
import zipfile
import shutil
import subprocess
import re
from datetime import datetime
from typing import Dict, Any, Optional, List, Tuple
import hashlib
from collections import Counter
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives.serialization import pkcs7
from cryptography import x509
import PyPDF2
from PIL import Image
import io


class PassGenerator:
    """Generates Apple Wallet passes from templates."""
    
    def __init__(self, certificates_path: str = None, assets_path: str = None):
        """Initialize the pass generator.
        
        Args:
            certificates_path: Path to directory containing pass certificates
            assets_path: Path to directory containing pass assets (icons, etc.)
        """
        self.certificates_path = certificates_path or os.path.join(os.path.dirname(__file__), "../../certificates")
        self.assets_path = assets_path or os.path.join(os.path.dirname(__file__), "../../assets")
        self.signing_enabled = self._check_certificates_available()
        
    def create_basic_pass(self, 
                         title: str = "Generic Pass", 
                         description: str = "Generated from PDF",
                         organization: str = "Add2Wallet") -> bytes:
        """Create a basic Apple Wallet pass.
        
        Args:
            title: Pass title
            description: Pass description  
            organization: Organization name
            
        Returns:
            bytes: The .pkpass file as bytes
        """
        
        # Extract identifiers from certificate
        pass_type_id, team_id = self._extract_certificate_identifiers()
        
        # Create pass.json
        pass_json = {
            "formatVersion": 1,
            "passTypeIdentifier": pass_type_id,
            "serialNumber": f"generic-{datetime.now().strftime('%Y%m%d%H%M%S')}",
            "teamIdentifier": team_id,
            "organizationName": organization,
            "description": description,
            "logoText": title,
            "foregroundColor": "rgb(255, 255, 255)",
            "backgroundColor": "rgb(60, 60, 67)",
            "labelColor": "rgb(255, 255, 255)",
            "generic": {
                "headerFields": [
                    {
                        "key": "header",
                        "label": "DOCUMENT",
                        "value": title
                    }
                ],
                "primaryFields": [
                    {
                        "key": "title",
                        "label": "",
                        "value": title
                    }
                ],
                "secondaryFields": [
                    {
                        "key": "description", 
                        "label": "Description",
                        "value": description
                    }
                ],
                "auxiliaryFields": [
                    {
                        "key": "generated",
                        "label": "Generated",
                        "value": datetime.now().strftime("%b %d, %Y")
                    }
                ]
            }
        }
        
        # Create temporary directory for pass files
        with tempfile.TemporaryDirectory() as temp_dir:
            
            # Write pass.json
            pass_json_path = os.path.join(temp_dir, "pass.json")
            with open(pass_json_path, 'w') as f:
                json.dump(pass_json, f, indent=2)
            
            # Copy icon files to pass directory
            self._copy_icon_assets(temp_dir)
            
            # Create manifest.json (file hashes)
            manifest = self._create_manifest(temp_dir)
            manifest_path = os.path.join(temp_dir, "manifest.json")
            with open(manifest_path, 'w') as f:
                json.dump(manifest, f, indent=2)
            
            # Sign the manifest if certificates are available
            if self.signing_enabled:
                signature = self._sign_manifest_file(manifest_path)
                signature_path = os.path.join(temp_dir, "signature")
                with open(signature_path, 'wb') as f:
                    f.write(signature)
            
            # Create .pkpass zip file
            pkpass_data = self._create_pkpass_zip(temp_dir)
            
            return pkpass_data
    
    def _copy_icon_assets(self, temp_dir: str) -> None:
        """Copy icon assets to the pass directory.
        
        Args:
            temp_dir: Temporary directory for pass files
        """
        icon_files = ['icon.png', 'icon@2x.png', 'icon@3x.png']
        
        for icon_file in icon_files:
            src_path = os.path.join(self.assets_path, icon_file)
            if os.path.exists(src_path):
                dst_path = os.path.join(temp_dir, icon_file)
                shutil.copy2(src_path, dst_path)
                print(f"✅ Copied {icon_file} to pass bundle")
            else:
                print(f"⚠️  Icon file not found: {src_path}")
    
    def _create_manifest(self, pass_dir: str) -> Dict[str, str]:
        """Create manifest.json with file hashes.
        
        Args:
            pass_dir: Directory containing pass files
            
        Returns:
            Dictionary mapping filenames to SHA1 hashes
        """
        manifest = {}
        
        for filename in os.listdir(pass_dir):
            if filename.startswith('.') or filename == 'manifest.json':
                continue
                
            file_path = os.path.join(pass_dir, filename)
            if os.path.isfile(file_path):
                with open(file_path, 'rb') as f:
                    file_hash = hashlib.sha1(f.read()).hexdigest()
                    manifest[filename] = file_hash
        
        return manifest
    
    def _create_pkpass_zip(self, pass_dir: str) -> bytes:
        """Create .pkpass zip file from pass directory.
        
        Args:
            pass_dir: Directory containing pass files
            
        Returns:
            The .pkpass file as bytes
        """
        zip_buffer = []
        
        with tempfile.NamedTemporaryFile() as temp_zip:
            with zipfile.ZipFile(temp_zip, 'w', zipfile.ZIP_DEFLATED) as zf:
                for filename in os.listdir(pass_dir):
                    if not filename.startswith('.'):
                        file_path = os.path.join(pass_dir, filename)
                        if os.path.isfile(file_path):
                            zf.write(file_path, filename)
            
            temp_zip.seek(0)
            return temp_zip.read()
    
    def create_pass_from_pdf_data(self, 
                                 pdf_data: bytes, 
                                 filename: str) -> bytes:
        """Create an intelligent pass from PDF data.
        
        Args:
            pdf_data: Raw PDF bytes
            filename: Original filename
            
        Returns:
            The .pkpass file as bytes
        """
        print(f"🔍 Analyzing PDF: {filename}")
        
        # Extract text content from PDF
        pdf_text = self._extract_pdf_text(pdf_data)
        print(f"📝 Extracted {len(pdf_text)} characters of text")
        
        # Analyze PDF content to extract pass information
        pass_info = self._extract_pass_info(pdf_text)
        print(f"🎯 Extracted info: {pass_info}")
        
        # Analyze colors for dynamic theming
        bg_color, fg_color, label_color = self._analyze_pdf_colors(pdf_data)
        print(f"🎨 Color theme: bg={bg_color}, fg={fg_color}")
        
        # Use extracted title or fallback to filename
        title = pass_info.get('title') or filename.replace('.pdf', '').replace('_', ' ').title()
        
        # Use extracted description or create one
        description = pass_info.get('description') or f"Digital pass from {filename}"
        
        return self.create_enhanced_pass(
            title=title,
            description=description,
            pass_info=pass_info,
            bg_color=bg_color,
            fg_color=fg_color,
            label_color=label_color
        )
    
    def create_enhanced_pass(self, 
                            title: str,
                            description: str,
                            pass_info: Dict[str, str],
                            bg_color: str,
                            fg_color: str,
                            label_color: str,
                            organization: str = "Add2Wallet") -> bytes:
        """Create an enhanced pass with extracted PDF data.
        
        Args:
            title: Pass title
            description: Pass description
            pass_info: Extracted information from PDF
            bg_color: Background color
            fg_color: Foreground color  
            label_color: Label color
            organization: Organization name
            
        Returns:
            bytes: The .pkpass file as bytes
        """
        # Extract identifiers from certificate
        pass_type_id, team_id = self._extract_certificate_identifiers()
        
        # Build pass fields dynamically based on extracted info
        header_fields = []
        primary_fields = []
        secondary_fields = []
        auxiliary_fields = []
        
        # Header field - always show document type or title
        if pass_info.get('title'):
            header_fields.append({
                "key": "header",
                "label": "EVENT",
                "value": title[:25]  # Limit length for header
            })
        else:
            header_fields.append({
                "key": "header", 
                "label": "DOCUMENT",
                "value": "Digital Pass"
            })
        
        # Primary field - main title
        primary_fields.append({
            "key": "title",
            "label": "",
            "value": title
        })
        
        # Secondary fields - date and time if available
        if pass_info.get('date'):
            secondary_fields.append({
                "key": "date",
                "label": "Date",
                "value": pass_info['date']
            })
            
        if pass_info.get('time'):
            secondary_fields.append({
                "key": "time", 
                "label": "Time",
                "value": pass_info['time']
            })
        
        # Auxiliary fields - venue and other details
        if pass_info.get('venue'):
            auxiliary_fields.append({
                "key": "venue",
                "label": "Venue",
                "value": pass_info['venue']
            })
            
        # Always add generation info
        auxiliary_fields.append({
            "key": "generated",
            "label": "Generated",
            "value": datetime.now().strftime("%b %d, %Y")
        })
        
        # Create pass.json with enhanced content
        pass_json = {
            "formatVersion": 1,
            "passTypeIdentifier": pass_type_id,
            "serialNumber": f"enhanced-{datetime.now().strftime('%Y%m%d%H%M%S')}",
            "teamIdentifier": team_id,
            "organizationName": organization,
            "description": description,
            "logoText": title[:20],  # Shorter for logo text
            "foregroundColor": fg_color,
            "backgroundColor": bg_color,
            "labelColor": label_color,
            "generic": {
                "headerFields": header_fields,
                "primaryFields": primary_fields,
                "secondaryFields": secondary_fields,
                "auxiliaryFields": auxiliary_fields
            }
        }
        
        # Create temporary directory for pass files
        with tempfile.TemporaryDirectory() as temp_dir:
            
            # Write pass.json
            pass_json_path = os.path.join(temp_dir, "pass.json")
            with open(pass_json_path, 'w') as f:
                json.dump(pass_json, f, indent=2)
            
            # Copy icon files to pass directory
            self._copy_icon_assets(temp_dir)
            
            # Create manifest.json (file hashes)
            manifest = self._create_manifest(temp_dir)
            manifest_path = os.path.join(temp_dir, "manifest.json")
            with open(manifest_path, 'w') as f:
                json.dump(manifest, f, indent=2)
            
            # Sign the manifest if certificates are available
            if self.signing_enabled:
                signature = self._sign_manifest_file(manifest_path)
                signature_path = os.path.join(temp_dir, "signature")
                with open(signature_path, 'wb') as f:
                    f.write(signature)
            
            # Create .pkpass zip file
            pkpass_data = self._create_pkpass_zip(temp_dir)
            
            return pkpass_data
    
    def _check_certificates_available(self) -> bool:
        """Check if all required certificate files are available.
        
        Returns:
            True if certificates are available for signing
        """
        required_files = ['pass.pem', 'key.pem']
        
        # Check basic required files
        for filename in required_files:
            file_path = os.path.join(self.certificates_path, filename)
            if not os.path.exists(file_path):
                print(f"⚠️  Certificate file not found: {filename}")
                return False
        
        # Check for WWDR certificate (prefer G4, fallback to regular)
        wwdrg4_path = os.path.join(self.certificates_path, 'wwdrg4.pem')
        wwdr_path = os.path.join(self.certificates_path, 'wwdr.pem')
        
        if os.path.exists(wwdrg4_path):
            print("✅ All certificate files found - signing enabled with WWDR G4")
        elif os.path.exists(wwdr_path):
            print("✅ All certificate files found - signing enabled with default WWDR")
        else:
            print("⚠️  No WWDR certificate found (need wwdrg4.pem or wwdr.pem)")
            return False
        
        return True
    
    def _extract_certificate_identifiers(self) -> tuple[str, str]:
        """Extract passTypeIdentifier and teamIdentifier from the certificate.
        
        Returns:
            tuple: (passTypeIdentifier, teamIdentifier)
        """
        if not self.signing_enabled:
            return "pass.com.andresboedo.add2wallet", "H9DPH4DQG7"
        
        try:
            pass_cert_path = os.path.join(self.certificates_path, 'pass.pem')
            with open(pass_cert_path, 'rb') as f:
                pass_cert = x509.load_pem_x509_certificate(f.read())
            
            # Extract UID from certificate subject (this is the passTypeIdentifier)
            pass_type_id = None
            team_id = None
            
            for attribute in pass_cert.subject:
                if attribute.oid._name == 'userID':  # UID field (note the capital D)
                    pass_type_id = attribute.value
                elif attribute.oid._name == 'organizationalUnitName':  # OU field  
                    team_id = attribute.value
            
            if pass_type_id and team_id:
                print(f"✅ Extracted from certificate: passTypeId={pass_type_id}, teamId={team_id}")
                return pass_type_id, team_id
            else:
                print("⚠️  Could not extract identifiers from certificate, using defaults")
                return "pass.com.andresboedo.add2wallet", "H9DPH4DQG7"
                
        except Exception as e:
            print(f"❌ Error extracting certificate identifiers: {e}")
            return "pass.com.andresboedo.add2wallet", "H9DPH4DQG7"
    
    def _sign_manifest_file(self, manifest_path: str) -> bytes:
        """Sign the manifest file with the pass certificate.
        
        Args:
            manifest_path: Path to the manifest.json file
            
        Returns:
            The signature bytes
        """
        if not self.signing_enabled:
            return b""
        
        try:
            # Load certificates
            pass_cert_path = os.path.join(self.certificates_path, 'pass.pem')
            key_path = os.path.join(self.certificates_path, 'key.pem')
            wwdr_cert_path = os.path.join(self.certificates_path, 'wwdr.pem')
            
            # Read the manifest file
            with open(manifest_path, 'rb') as f:
                manifest_data = f.read()
            
            # Load the pass certificate
            with open(pass_cert_path, 'rb') as f:
                pass_cert = x509.load_pem_x509_certificate(f.read())
            
            # Load the private key
            with open(key_path, 'rb') as f:
                private_key = serialization.load_pem_private_key(f.read(), password=None)
            
            # Load the WWDR certificate - use G4 for passes issued by G4
            wwdrg4_cert_path = os.path.join(self.certificates_path, 'wwdrg4.pem')
            if os.path.exists(wwdrg4_cert_path):
                with open(wwdrg4_cert_path, 'rb') as f:
                    wwdr_cert = x509.load_pem_x509_certificate(f.read())
                print("🔗 Using WWDR G4 certificate for signing")
            else:
                # Fallback to regular WWDR certificate
                with open(wwdr_cert_path, 'rb') as f:
                    wwdr_cert = x509.load_pem_x509_certificate(f.read())
                print("🔗 Using default WWDR certificate for signing")
            
            # Try using OpenSSL command line for more reliable signing
            signature = self._sign_manifest_with_openssl(manifest_path)
            if not signature:
                # Fallback to Python cryptography library
                with open(manifest_path, 'rb') as f:
                    manifest_data = f.read()
                
                options = [pkcs7.PKCS7Options.DetachedSignature]
                signature = pkcs7.PKCS7SignatureBuilder().set_data(
                    manifest_data
                ).add_signer(
                    pass_cert, private_key, hashes.SHA256()  # Use SHA256 as required by cryptography
                ).add_certificate(
                    wwdr_cert
                ).sign(
                    serialization.Encoding.DER, options
                )
            
            return signature
            
        except Exception as e:
            print(f"❌ Error signing manifest: {e}")
            return b""
    
    def _sign_manifest(self, manifest_data: bytes) -> bytes:
        """Legacy method - kept for compatibility.
        
        Args:
            manifest_data: The manifest.json file as bytes
            
        Returns:
            The signature bytes
        """
        # Write manifest to temp file and sign it
        with tempfile.NamedTemporaryFile(mode='wb', delete=False) as f:
            f.write(manifest_data)
            temp_path = f.name
        
        try:
            signature = self._sign_manifest_file(temp_path)
            return signature
        finally:
            os.unlink(temp_path)
    
    def _sign_manifest_with_openssl(self, manifest_path: str) -> bytes:
        """Sign manifest using OpenSSL command line for better compatibility.
        
        Args:
            manifest_path: Path to the manifest.json file
            
        Returns:
            The signature bytes, or empty bytes if signing fails
        """
        if not self.signing_enabled:
            return b""
        
        try:
            pass_cert_path = os.path.join(self.certificates_path, 'pass.pem')
            key_path = os.path.join(self.certificates_path, 'key.pem')
            
            # Determine which WWDR certificate to use
            wwdrg4_cert_path = os.path.join(self.certificates_path, 'wwdrg4.pem')
            wwdr_cert_path = os.path.join(self.certificates_path, 'wwdr.pem')
            
            if os.path.exists(wwdrg4_cert_path):
                wwdr_path = wwdrg4_cert_path
            else:
                wwdr_path = wwdr_cert_path
            
            # Create a temporary file for the signature
            with tempfile.NamedTemporaryFile(delete=False, suffix='.der') as sig_file:
                sig_path = sig_file.name
            
            # For Apple Wallet, we need to create the signature in a specific way
            # First, let's try the exact OpenSSL approach Apple expects
            cmd = [
                'openssl', 'smime', '-sign',
                '-binary',
                '-signer', pass_cert_path,
                '-inkey', key_path,
                '-certfile', wwdr_path,
                '-in', manifest_path,
                '-out', sig_path,
                '-outform', 'DER'
            ]
            
            print(f"🔐 Signing with OpenSSL: {' '.join(cmd)}")
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                # Read the signature
                with open(sig_path, 'rb') as f:
                    signature = f.read()
                
                print(f"✅ OpenSSL signing successful: {len(signature)} bytes")
                
                # Clean up
                os.unlink(sig_path)
                
                return signature
            else:
                print(f"❌ OpenSSL signing failed: {result.stderr}")
                # Clean up
                if os.path.exists(sig_path):
                    os.unlink(sig_path)
                return b""
                
        except Exception as e:
            print(f"❌ Error with OpenSSL signing: {e}")
            return b""
    
    def _extract_pdf_text(self, pdf_data: bytes) -> str:
        """Extract text content from PDF.
        
        Args:
            pdf_data: Raw PDF bytes
            
        Returns:
            Extracted text content
        """
        try:
            pdf_reader = PyPDF2.PdfReader(io.BytesIO(pdf_data))
            text_content = ""
            
            for page in pdf_reader.pages:
                text_content += page.extract_text() + "\n"
            
            return text_content.strip()
            
        except Exception as e:
            print(f"❌ Error extracting PDF text: {e}")
            return ""
    
    def _analyze_pdf_colors(self, pdf_data: bytes) -> Tuple[str, str, str]:
        """Analyze PDF to suggest color palette.
        
        Args:
            pdf_data: Raw PDF bytes
            
        Returns:
            tuple: (background_color, foreground_color, label_color)
        """
        # For now, return a smart default palette based on common ticket colors
        # This is a simplified approach - full implementation would analyze actual PDF colors
        
        try:
            text = self._extract_pdf_text(pdf_data).lower()
            
            # Simple color inference based on content type
            if any(word in text for word in ['airline', 'flight', 'boarding']):
                return "rgb(0, 122, 255)", "rgb(255, 255, 255)", "rgb(255, 255, 255)"  # Blue theme
            elif any(word in text for word in ['concert', 'music', 'show', 'festival']):
                return "rgb(255, 45, 85)", "rgb(255, 255, 255)", "rgb(255, 255, 255)"   # Red theme
            elif any(word in text for word in ['train', 'railway', 'rail']):
                return "rgb(48, 176, 199)", "rgb(255, 255, 255)", "rgb(255, 255, 255)"  # Teal theme
            elif any(word in text for word in ['hotel', 'reservation', 'check']):
                return "rgb(142, 142, 147)", "rgb(255, 255, 255)", "rgb(255, 255, 255)" # Gray theme
            else:
                # Default professional blue
                return "rgb(0, 122, 255)", "rgb(255, 255, 255)", "rgb(255, 255, 255)"
                
        except Exception as e:
            print(f"⚠️  Error analyzing PDF colors: {e}")
            return "rgb(0, 122, 255)", "rgb(255, 255, 255)", "rgb(255, 255, 255)"
    
    def _extract_pass_info(self, pdf_text: str) -> Dict[str, str]:
        """Extract basic pass information from PDF text.
        
        Args:
            pdf_text: Extracted text from PDF
            
        Returns:
            Dictionary with extracted information
        """
        info = {
            'title': '',
            'event_name': '',
            'date': '',
            'time': '',
            'venue': '',
            'description': ''
        }
        
        lines = [line.strip() for line in pdf_text.split('\n') if line.strip()]
        
        if not lines:
            return info
        
        # Extract title (usually one of the first meaningful lines)
        for line in lines[:5]:
            if len(line) > 3 and not re.match(r'^[\d\s\-\+\(\)]+$', line):
                info['title'] = line[:50]  # Limit title length
                break
        
        # Extract dates (look for various date formats)
        date_patterns = [
            r'\b(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})\b',  # MM/DD/YYYY, DD-MM-YYYY
            r'\b(\d{4}[\/\-\.]\d{1,2}[\/\-\.]\d{1,2})\b',     # YYYY-MM-DD
            r'\b((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]* \d{1,2},? \d{4})\b',  # Month DD, YYYY
            r'\b(\d{1,2} (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]* \d{4})\b'     # DD Month YYYY
        ]
        
        for pattern in date_patterns:
            match = re.search(pattern, pdf_text, re.IGNORECASE)
            if match:
                info['date'] = match.group(1)
                break
        
        # Extract times (look for time formats)
        time_patterns = [
            r'\b(\d{1,2}:\d{2}\s*(?:AM|PM))\b',  # 12-hour format
            r'\b(\d{1,2}:\d{2})\b'               # 24-hour format
        ]
        
        for pattern in time_patterns:
            match = re.search(pattern, pdf_text, re.IGNORECASE)
            if match:
                info['time'] = match.group(1)
                break
        
        # Extract venue/location (look for common venue indicators)
        venue_indicators = ['venue:', 'location:', 'address:', 'at:', '@']
        for line in lines:
            line_lower = line.lower()
            for indicator in venue_indicators:
                if indicator in line_lower:
                    venue_text = line[line_lower.find(indicator) + len(indicator):].strip()
                    if len(venue_text) > 3:
                        info['venue'] = venue_text[:100]  # Limit venue length
                        break
            if info['venue']:
                break
        
        # Create description
        if info.get('date') or info.get('time') or info.get('venue'):
            desc_parts = []
            if info.get('date'):
                desc_parts.append(info['date'])
            if info.get('time'):
                desc_parts.append(info['time'])
            if info.get('venue'):
                desc_parts.append(info['venue'])
            info['description'] = " • ".join(desc_parts)
        
        return info


# Global instance
pass_generator = PassGenerator()