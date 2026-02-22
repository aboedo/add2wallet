"""Clean barcode extraction → validation → PKBarcode mapping.

Wraps the existing BarcodeExtractor and normalises results into
ExtractedBarcode objects that are safe to embed in pass.json.
"""

from __future__ import annotations

from typing import List, Tuple

from app.services.v2.models import (
    BARCODE_FORMAT_MAP,
    UNSUPPORTED_FORMATS,
    ExtractedBarcode,
)


def extract_barcodes(
    pdf_bytes: bytes,
    filename: str,
) -> Tuple[List[ExtractedBarcode], List[str]]:
    """Extract and normalise barcodes from a PDF.

    Returns:
        (barcodes, warnings) where warnings contains human-readable messages
        about any unsupported formats that were skipped.
    """
    from app.services.barcode_extractor import barcode_extractor  # reuse v1

    raw_barcodes = barcode_extractor.extract_barcodes_from_pdf(pdf_bytes, filename)
    print(f"📊 Raw barcode detector found {len(raw_barcodes)} candidate(s)")

    # Sort by page then by descending area (same as v1)
    try:
        def _area(bc: dict) -> int:
            pos = bc.get("position") or {}
            return int((pos.get("width") or 0) * (pos.get("height") or 0))

        raw_barcodes.sort(key=lambda bc: (bc.get("page") or 0, -_area(bc)))
    except Exception:
        pass

    extracted: List[ExtractedBarcode] = []
    warnings: List[str] = []

    for bc in raw_barcodes:
        source_type: str = bc.get("type", "QRCODE").upper()

        # Skip unsupported formats
        if source_type in UNSUPPORTED_FORMATS:
            msg = (
                "This PDF contains a Data Matrix code, which is not supported by "
                "Apple Wallet. The pass has been saved without a barcode."
            )
            print(f"⚠️ Skipping {source_type} barcode — {msg}")
            if msg not in warnings:
                warnings.append(msg)
            continue

        pk_format = BARCODE_FORMAT_MAP.get(source_type, "PKBarcodeFormatQR")

        # Prefer raw bytes for message fidelity (use latin-1 mapping)
        raw_bytes: bytes | None = bc.get("raw_bytes")
        if raw_bytes is not None and isinstance(raw_bytes, (bytes, bytearray)):
            try:
                message = bytes(raw_bytes).decode("latin-1")
            except Exception:
                message = bc.get("data", "")
        else:
            message = str(bc.get("data", "")).replace("\r\n", "\n").strip("\n")

        if not message:
            print(f"⚠️ Barcode from {source_type} has empty payload — skipping")
            continue

        extracted.append(
            ExtractedBarcode(
                pk_format=pk_format,
                message=message,
                message_encoding="iso-8859-1",
                raw_bytes=raw_bytes,
                source_type=source_type,
                confidence=bc.get("confidence", 0),
            )
        )
        print(f"✅ Barcode: {source_type} → {pk_format}, {len(message)} chars")

    return extracted, warnings
