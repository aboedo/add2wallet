"""Integration tests for Peñarol PDF and PDF417 barcode support.

Regression suite to ensure:
1. Peñarol.pdf → 1 pass with PDF417 barcode (not 6 QR codes)
2. zxing-cpp correctly detects PDF417 where pyzbar fails
3. Other PDFs with PDF417 (Abu Dhabi, Madrid-Medellín) also work
"""

import io
import json
import os
import zipfile

import pytest

from app.services.barcode_extractor import BarcodeExtractor
from app.services.pass_generator import PassGenerator

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

TEST_FILES_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "test-files",
    "ignacio-feedback",
)


def _load(filename: str) -> bytes:
    path = os.path.join(TEST_FILES_DIR, filename)
    if not os.path.exists(path):
        pytest.skip(f"{filename} not found at {path}")
    with open(path, "rb") as f:
        return f.read()


def _pass_json(pkpass_bytes: bytes) -> dict:
    """Extract pass.json from a .pkpass (zip) file."""
    with zipfile.ZipFile(io.BytesIO(pkpass_bytes)) as z:
        return json.loads(z.read("pass.json"))


# ---------------------------------------------------------------------------
# Barcode extractor — unit-level
# ---------------------------------------------------------------------------


class TestPenarolBarcodeExtraction:
    """pyzbar cannot read the Peñarol PDF417; zxing-cpp must pick it up."""

    @pytest.fixture(scope="class")
    def extractor(self):
        return BarcodeExtractor()

    @pytest.fixture(scope="class")
    def barcodes(self, extractor):
        data = _load("12-Penarol.pdf")
        return extractor.extract_barcodes_from_pdf(data, "12-Penarol.pdf")

    def test_exactly_one_barcode(self, barcodes):
        """Must return exactly 1 barcode — no false positives from PDF text."""
        assert len(barcodes) == 1, (
            f"Expected 1 barcode, got {len(barcodes)}: "
            f"{[(b.get('type'), b.get('data', '')[:40]) for b in barcodes]}"
        )

    def test_format_is_pdf417(self, barcodes):
        """Barcode must be PDF417, not QR."""
        bc = barcodes[0]
        assert bc["type"] == "PDF417", f"Expected PDF417, got {bc['type']}"
        assert bc["format"] == "PKBarcodeFormatPDF417", f"Wrong PKBarcodeFormat: {bc['format']}"

    def test_detected_by_zxing(self, barcodes):
        """Must be detected by zxing-cpp (pyzbar cannot read this PDF417)."""
        bc = barcodes[0]
        assert bc.get("source") == "zxing", f"Expected source=zxing, got {bc.get('source')}"

    def test_not_a_false_positive_from_pdf_text(self, barcodes):
        """The AUF RUT number (214368590014) must NOT appear as a barcode."""
        data_values = [bc.get("data", "") for bc in barcodes]
        assert "214368590014" not in data_values, (
            "214368590014 is the AUF RUT from PDF text, not a barcode — "
            "it should be filtered out"
        )

    def test_barcode_has_raw_bytes(self, barcodes):
        bc = barcodes[0]
        assert "raw_bytes" in bc, "Barcode must have raw_bytes"
        assert isinstance(bc["raw_bytes"], bytes), "raw_bytes must be bytes"
        assert len(bc["raw_bytes"]) > 0, "raw_bytes must not be empty"


# ---------------------------------------------------------------------------
# Pass generator — one pass with PDF417
# ---------------------------------------------------------------------------


class TestPenarolPassGeneration:
    """End-to-end: Peñarol PDF → 1 .pkpass with PDF417."""

    @pytest.fixture(scope="class")
    def generation_result(self):
        pg = PassGenerator()
        data = _load("12-Penarol.pdf")
        return pg.create_pass_from_pdf_data(data, "12-Penarol.pdf", ai_metadata=None)

    def test_generates_exactly_one_pass(self, generation_result):
        pkpass_files, _, _, _ = generation_result
        assert len(pkpass_files) == 1, f"Expected 1 pass, got {len(pkpass_files)}"

    def test_pass_json_barcode_format_is_pdf417(self, generation_result):
        pkpass_files, _, _, _ = generation_result
        pj = _pass_json(pkpass_files[0])

        barcodes_entry = pj.get("barcodes", []) or [pj.get("barcode", {})]
        assert barcodes_entry, "pass.json must have barcodes"

        fmt = barcodes_entry[0].get("format")
        assert fmt == "PKBarcodeFormatPDF417", (
            f"Expected PKBarcodeFormatPDF417 in pass.json, got {fmt}"
        )

    def test_pass_is_valid_zip(self, generation_result):
        pkpass_files, _, _, _ = generation_result
        try:
            with zipfile.ZipFile(io.BytesIO(pkpass_files[0])) as z:
                names = z.namelist()
        except zipfile.BadZipFile:
            pytest.fail("Generated .pkpass is not a valid zip file")
        assert "pass.json" in names, "pass.json missing from .pkpass"

    def test_no_false_positive_tickets(self, generation_result):
        _, _, ticket_info, _ = generation_result
        assert len(ticket_info) == 1, (
            f"Expected 1 ticket, got {len(ticket_info)} — "
            "false positives from PDF text may be leaking through"
        )


# ---------------------------------------------------------------------------
# Regression: other PDF417 PDFs still work
# ---------------------------------------------------------------------------


class TestOtherPDF417Files:
    """Other PDFs with PDF417 barcodes should also produce the correct format."""

    @pytest.fixture(scope="class")
    def extractor(self):
        return BarcodeExtractor()

    @pytest.mark.parametrize("filename", [
        "2-AbuDhabi-Madrid.pdf",
        "7-Madrid-Medellin.pdf",
    ])
    def test_pdf417_detected(self, extractor, filename):
        data = _load(filename)
        barcodes = extractor.extract_barcodes_from_pdf(data, filename)
        pdf417 = [bc for bc in barcodes if bc.get("format") == "PKBarcodeFormatPDF417"]
        assert pdf417, (
            f"{filename}: expected at least one PDF417 barcode, "
            f"got: {[(bc.get('type'), bc.get('format')) for bc in barcodes]}"
        )


# ---------------------------------------------------------------------------
# Regression: existing PDFs not broken
# ---------------------------------------------------------------------------


class TestNoRegressions:
    """QR-based PDFs must still produce QR barcodes."""

    @pytest.fixture(scope="class")
    def extractor(self):
        return BarcodeExtractor()

    @pytest.mark.parametrize("filename,expected_count,expected_type", [
        ("13-Oppenheimer.pdf", 1, "QRCODE"),
        ("6-Cine-Gladiador.pdf", 1, "QRCODE"),
    ])
    def test_qr_pdfs_unaffected(self, extractor, filename, expected_count, expected_type):
        data = _load(filename)
        barcodes = extractor.extract_barcodes_from_pdf(data, filename)
        assert len(barcodes) == expected_count, (
            f"{filename}: expected {expected_count} barcode(s), got {len(barcodes)}"
        )
        assert barcodes[0]["type"] == expected_type, (
            f"{filename}: expected {expected_type}, got {barcodes[0]['type']}"
        )
