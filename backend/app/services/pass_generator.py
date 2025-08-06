"""Apple Wallet Pass Generator Service."""

import json
import os
import tempfile
import zipfile
from datetime import datetime
from typing import Dict, Any, Optional
import hashlib
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives.serialization import pkcs7
from cryptography import x509


class PassGenerator:
    """Generates Apple Wallet passes from templates."""
    
    def __init__(self, certificates_path: str = None):
        """Initialize the pass generator.
        
        Args:
            certificates_path: Path to directory containing pass certificates
        """
        self.certificates_path = certificates_path or os.path.join(os.path.dirname(__file__), "../../certificates")
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
        
        # Create pass.json
        pass_json = {
            "formatVersion": 1,
            "passTypeIdentifier": "pass.com.andresboedo.add2wallet.generic",
            "serialNumber": f"generic-{datetime.now().strftime('%Y%m%d%H%M%S')}",
            "teamIdentifier": "H9DPH4DQG7",
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
        required_files = ['pass.pem', 'key.pem', 'wwdr.pem']
        
        for filename in required_files:
            file_path = os.path.join(self.certificates_path, filename)
            if not os.path.exists(file_path):
                print(f"⚠️  Certificate file not found: {filename}")
                return False
        
        print("✅ All certificate files found - signing enabled")
        return True
    
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
            
            # Load the WWDR certificate
            with open(wwdr_cert_path, 'rb') as f:
                wwdr_cert = x509.load_pem_x509_certificate(f.read())
            
            # Create PKCS#7 signature
            options = [pkcs7.PKCS7Options.DetachedSignature]
            signature = pkcs7.PKCS7SignatureBuilder().set_data(
                manifest_data
            ).add_signer(
                pass_cert, private_key, hashes.SHA256()
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


# Global instance
pass_generator = PassGenerator()