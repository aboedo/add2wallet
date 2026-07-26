"""Regression tests for barcode format-name normalization.

zxing-cpp reports display names ('QR Code', 'Code 128', 'Data Matrix') while
pyzbar reports compact ones ('QRCODE', 'CODE128'). Every lookup downstream —
PKBarcodeFormat maps, format_groups, the DATAMATRIX guards in pass_generator —
keys on the compact spelling, so an unnormalized name fell through to the
default and produced a QR barcode for documents that were not QR codes.
"""

import os

import pytest

from app.core.barcodes import BARCODE_FORMAT_MAP, BarcodeScanner, _canonical
from app.core.models import DocumentKind
from app.services.barcode_extractor import canonical_format_name


TEST_FILES = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "test_files")


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("QR Code", "QRCODE"),
        ("QRCODE", "QRCODE"),
        ("QR_CODE", "QRCODE"),
        ("Code 128", "CODE128"),
        ("Code 39", "CODE39"),
        ("Data Matrix", "DATAMATRIX"),
        ("DATA_MATRIX", "DATAMATRIX"),
        ("PDF417", "PDF417"),
        ("Aztec", "AZTEC"),
        ("EAN-13", "EAN13"),
        ("UPC-A", "UPCA"),
        (None, ""),
    ],
)
def test_canonical_format_name_collapses_detector_spellings(raw, expected):
    assert canonical_format_name(raw) == expected
    assert _canonical(raw) == expected


@pytest.mark.parametrize(
    ("display_name", "expected_pk_format"),
    [
        ("QR Code", "PKBarcodeFormatQR"),
        ("Code 128", "PKBarcodeFormatCode128"),
        ("Code 39", "PKBarcodeFormatCode128"),
        ("PDF417", "PKBarcodeFormatPDF417"),
        ("Aztec", "PKBarcodeFormatAztec"),
    ],
)
def test_zxing_display_names_map_to_correct_pk_format(display_name, expected_pk_format):
    """A Code 128 must not silently become a QR barcode in the pass."""
    assert BARCODE_FORMAT_MAP[_canonical(display_name)] == expected_pk_format


def test_data_matrix_is_reported_unsupported_not_emitted_as_qr():
    """Apple Wallet cannot render Data Matrix; the user must be warned.

    Before normalization this produced a pass whose QR barcode encoded a Data
    Matrix payload, with no warning at all.
    """
    path = os.path.join(TEST_FILES, "pass_with_data_matrix.pdf")
    if not os.path.exists(path):
        pytest.skip(f"Test file not found: {path}")

    with open(path, "rb") as handle:
        pdf_data = handle.read()

    barcodes, warnings = BarcodeScanner().scan(pdf_data, DocumentKind.pdf, "pass_with_data_matrix.pdf")

    assert not any(bc.pk_format == "PKBarcodeFormatQR" for bc in barcodes), (
        f"Data Matrix leaked through as a QR barcode: {[(b.type, b.pk_format) for b in barcodes]}"
    )
    assert any("Data Matrix" in warning for warning in warnings), (
        f"Expected an unsupported-format warning, got: {warnings}"
    )
