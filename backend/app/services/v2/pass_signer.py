"""Certificate loading, manifest creation and pass signing for Apple Wallet."""

from __future__ import annotations

import base64
import hashlib
import io
import json
import os
import tempfile
import zipfile
from typing import Dict, Optional, Tuple

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.serialization import pkcs7
from cryptography.x509.oid import NameOID


class PassSigner:
    """Handles certificate loading, manifest creation and .pkpass signing."""

    def __init__(self, certificates_path: Optional[str] = None) -> None:
        self.certificates_path = certificates_path or os.path.join(
            os.path.dirname(__file__), "../../../certificates"
        )
        self.signing_enabled = self._check_certificates_available()

    # ------------------------------------------------------------------
    # Public helpers
    # ------------------------------------------------------------------

    def get_identifiers(self) -> Tuple[str, str]:
        """Return (passTypeIdentifier, teamIdentifier) from the certificate."""
        if not self.signing_enabled:
            return "pass.com.andresboedo.add2wallet", "H9DPH4DQG7"

        try:
            cert = self._load_pass_cert()
            pass_type_id: Optional[str] = None
            team_id: Optional[str] = None

            try:
                uid_attrs = cert.subject.get_attributes_for_oid(NameOID.USER_ID)
                if uid_attrs:
                    pass_type_id = uid_attrs[0].value
            except Exception:
                pass

            try:
                ou_attrs = cert.subject.get_attributes_for_oid(NameOID.ORGANIZATIONAL_UNIT_NAME)
                if ou_attrs:
                    team_id = ou_attrs[0].value
            except Exception:
                pass

            if pass_type_id and team_id:
                return pass_type_id, team_id

        except Exception as exc:
            print(f"⚠️ Could not extract certificate identifiers: {exc}")

        return "pass.com.andresboedo.add2wallet", "H9DPH4DQG7"

    def create_manifest(self, pass_dir: str) -> Dict[str, str]:
        """Return SHA-1 manifest dict for all files in pass_dir."""
        manifest: Dict[str, str] = {}
        for filename in sorted(os.listdir(pass_dir)):
            if filename.startswith(".") or filename == "manifest.json":
                continue
            file_path = os.path.join(pass_dir, filename)
            if os.path.isfile(file_path):
                with open(file_path, "rb") as f:
                    manifest[filename] = hashlib.sha1(f.read()).hexdigest()
        return manifest

    def sign_manifest(self, manifest_path: str) -> bytes:
        """Sign manifest.json and return DER-encoded detached CMS signature."""
        if not self.signing_enabled:
            return b""

        try:
            pass_cert, private_key, wwdr_cert = self._load_all_certs()

            with open(manifest_path, "rb") as f:
                manifest_data = f.read()

            digest_name = os.getenv("PASS_SIGNATURE_DIGEST", "sha256").lower()
            digest_algo = hashes.SHA1() if "sha1" in digest_name else hashes.SHA256()

            signature = (
                pkcs7.PKCS7SignatureBuilder()
                .set_data(manifest_data)
                .add_signer(pass_cert, private_key, digest_algo)
                .add_certificate(wwdr_cert)
                .sign(serialization.Encoding.DER, [
                    pkcs7.PKCS7Options.DetachedSignature,
                    pkcs7.PKCS7Options.Binary,
                ])
            )
            return signature

        except Exception as exc:
            print(f"❌ Signing failed: {exc}")
            return b""

    def build_pkpass(self, pass_dir: str) -> bytes:
        """Zip pass_dir contents into a .pkpass bytes blob."""
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
            for filename in os.listdir(pass_dir):
                if not filename.startswith("."):
                    file_path = os.path.join(pass_dir, filename)
                    if os.path.isfile(file_path):
                        zf.write(file_path, filename)
        buf.seek(0)
        return buf.read()

    def package_pass(self, pass_dir: str) -> bytes:
        """Create manifest, sign, and zip the pass directory into .pkpass bytes."""
        # Write manifest.json
        manifest = self.create_manifest(pass_dir)
        manifest_path = os.path.join(pass_dir, "manifest.json")
        with open(manifest_path, "w") as f:
            json.dump(manifest, f, indent=2)

        # Sign manifest if certs are available
        if self.signing_enabled:
            sig = self.sign_manifest(manifest_path)
            if sig:
                sig_path = os.path.join(pass_dir, "signature")
                with open(sig_path, "wb") as f:
                    f.write(sig)
            else:
                print("⚠️ Signing produced empty bytes — pass will be unsigned")

        return self.build_pkpass(pass_dir)

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _check_certificates_available(self) -> bool:
        # Prefer env-var certs (Railway / Vercel)
        if (
            os.getenv("PASS_CERT_PEM")
            and os.getenv("PASS_KEY_PEM")
            and os.getenv("WWDR_CERT_PEM")
        ):
            print("✅ Certificates found in environment variables — signing enabled")
            return True

        # Fallback to file-based certs
        required = ["pass.pem", "key.pem"]
        for filename in required:
            if not os.path.exists(os.path.join(self.certificates_path, filename)):
                print(f"⚠️ Certificate file not found: {filename}")
                return False

        wwdr_g4 = os.path.join(self.certificates_path, "wwdrg4.pem")
        wwdr = os.path.join(self.certificates_path, "wwdr.pem")
        if not os.path.exists(wwdr_g4) and not os.path.exists(wwdr):
            print("⚠️ No WWDR certificate found (need wwdrg4.pem or wwdr.pem)")
            return False

        print("✅ All certificate files found — signing enabled")
        return True

    def _load_pass_cert(self) -> x509.Certificate:
        if os.getenv("PASS_CERT_PEM"):
            data = base64.b64decode(os.getenv("PASS_CERT_PEM"))  # type: ignore[arg-type]
            return x509.load_pem_x509_certificate(data)
        path = os.path.join(self.certificates_path, "pass.pem")
        with open(path, "rb") as f:
            return x509.load_pem_x509_certificate(f.read())

    def _load_all_certs(self) -> Tuple[x509.Certificate, object, x509.Certificate]:
        """Return (pass_cert, private_key, wwdr_cert)."""
        if os.getenv("PASS_CERT_PEM"):
            pass_cert = x509.load_pem_x509_certificate(
                base64.b64decode(os.getenv("PASS_CERT_PEM"))  # type: ignore[arg-type]
            )
            private_key = serialization.load_pem_private_key(
                base64.b64decode(os.getenv("PASS_KEY_PEM")), password=None  # type: ignore[arg-type]
            )
            wwdr_cert = x509.load_pem_x509_certificate(
                base64.b64decode(os.getenv("WWDR_CERT_PEM"))  # type: ignore[arg-type]
            )
            print("🔗 Using certificates from environment variables")
            return pass_cert, private_key, wwdr_cert

        cert_path = os.path.join(self.certificates_path, "pass.pem")
        key_path = os.path.join(self.certificates_path, "key.pem")

        with open(cert_path, "rb") as f:
            pass_cert = x509.load_pem_x509_certificate(f.read())
        with open(key_path, "rb") as f:
            private_key = serialization.load_pem_private_key(f.read(), password=None)

        wwdr_g4 = os.path.join(self.certificates_path, "wwdrg4.pem")
        wwdr = os.path.join(self.certificates_path, "wwdr.pem")
        wwdr_path = wwdr_g4 if os.path.exists(wwdr_g4) else wwdr

        with open(wwdr_path, "rb") as f:
            wwdr_cert = x509.load_pem_x509_certificate(f.read())

        label = "G4" if os.path.exists(wwdr_g4) else "default"
        print(f"🔗 Using WWDR {label} certificate for signing")
        return pass_cert, private_key, wwdr_cert


# Global instance — lazily created so import doesn't fail if certs are missing
_signer: Optional[PassSigner] = None


def get_signer() -> PassSigner:
    global _signer
    if _signer is None:
        _signer = PassSigner()
    return _signer
