"""Apple Wallet Pass Generator Service."""

import json
import os
import tempfile
import zipfile
import shutil
import subprocess
from datetime import datetime
from typing import Dict, Any, Optional
import hashlib
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives.serialization import pkcs7
from cryptography import x509


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
        """Create a pass from PDF data.
        
        Args:
            pdf_data: Raw PDF bytes
            filename: Original filename
            
        Returns:
            The .pkpass file as bytes
        """
        # For now, create a basic pass with PDF info
        # In future versions, we'd extract more info from the PDF
        
        title = filename.replace('.pdf', '').replace('_', ' ').title()
        description = f"Digital pass generated from {filename}"
        
        return self.create_basic_pass(title=title, description=description)
    
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


# Global instance
pass_generator = PassGenerator()