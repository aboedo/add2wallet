from __future__ import annotations

import logging
import re
from typing import Any

import numpy as np

from app.core.images import load_upload_image
from app.core.models import Barcode, DocumentKind


logger = logging.getLogger(__name__)

# Keys are canonical format names (see _canonical): uppercase, alphanumerics
# only. Detectors disagree on spelling — pyzbar says "QRCODE", zxing-cpp says
# "QR Code" — and an unmatched key silently fell back to a QR barcode, which
# produced unscannable passes for Code128/Code39 and Data Matrix documents.
BARCODE_FORMAT_MAP = {
    "QRCODE": "PKBarcodeFormatQR",
    "CODE128": "PKBarcodeFormatCode128",
    "PDF417": "PKBarcodeFormatPDF417",
    "AZTEC": "PKBarcodeFormatAztec",
    "CODE39": "PKBarcodeFormatCode128",
    "CODE93": "PKBarcodeFormatCode128",
    "EAN13": "PKBarcodeFormatCode128",
    "EAN8": "PKBarcodeFormatCode128",
    "UPCA": "PKBarcodeFormatCode128",
    "UPCE": "PKBarcodeFormatCode128",
    "ITF": "PKBarcodeFormatCode128",
    "CODABAR": "PKBarcodeFormatCode128",
}

UNSUPPORTED = {"DATAMATRIX"}


def _canonical(raw: Any) -> str:
    """Uppercase and strip separators so every detector's spelling agrees."""
    return re.sub(r"[^A-Z0-9]", "", str(raw or "").upper())


class BarcodeScanner:
    def scan(self, data: bytes, kind: DocumentKind, filename: str) -> tuple[list[Barcode], list[str]]:
        if kind is DocumentKind.pdf:
            return self._scan_pdf(data, filename)
        return self._scan_image(data, kind)

    def _scan_pdf(self, data: bytes, filename: str) -> tuple[list[Barcode], list[str]]:
        try:
            from app.services.barcode_extractor import barcode_extractor

            raw = barcode_extractor.extract_barcodes_from_pdf(data, filename)
            return _normalize(raw)
        except Exception:
            logger.warning("PDF barcode scanner failed", exc_info=True)
            return [], ["Barcode scanning failed; pass was created without a barcode."]

    def _scan_image(self, data: bytes, kind: DocumentKind) -> tuple[list[Barcode], list[str]]:
        warnings: list[str] = []
        raw: list[dict[str, Any]] = []
        try:
            image = load_upload_image(data, kind)
        except Exception:
            logger.info("Image barcode scan could not decode image", exc_info=True)
            return [], ["Barcode scanning failed; pass was created without a barcode."]

        try:
            from pyzbar import pyzbar

            for decoded in pyzbar.decode(image):
                payload = decoded.data.decode("latin-1") if decoded.data else ""
                raw.append(
                    {
                        "type": decoded.type,
                        "data": payload,
                        "raw_bytes": decoded.data,
                        "confidence": 90,
                    }
                )
        except Exception:
            logger.info("pyzbar image scan unavailable or found no barcode", exc_info=True)

        if not raw:
            try:
                import cv2


                rgb = np.array(image)
                img = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
                detector = cv2.QRCodeDetector()
                decoded, _, _ = detector.detectAndDecode(img)
                if decoded:
                    raw.append({"type": "QRCODE", "data": decoded, "confidence": 80})
            except Exception:
                logger.info("OpenCV image QR scan unavailable", exc_info=True)

        normalized, normalize_warnings = _normalize(raw)
        return normalized, warnings + normalize_warnings


def _normalize(raw: list[dict[str, Any]]) -> tuple[list[Barcode], list[str]]:
    warnings: list[str] = []
    results: list[Barcode] = []
    seen: set[tuple[str, str]] = set()
    for item in raw:
        source_type = _canonical(item.get("type")) or "QRCODE"
        if source_type in UNSUPPORTED:
            message = (
                "This document contains a Data Matrix code, which is not supported by Apple Wallet. "
                "The pass has been saved without that barcode."
            )
            if message not in warnings:
                warnings.append(message)
            continue
        pk_format = BARCODE_FORMAT_MAP.get(source_type, "PKBarcodeFormatQR")
        raw_bytes = item.get("raw_bytes")
        if isinstance(raw_bytes, (bytes, bytearray)):
            value = bytes(raw_bytes).decode("latin-1", errors="ignore")
        else:
            value = str(item.get("data") or "").strip()
        if not value:
            continue
        key = (source_type, value)
        if key in seen:
            continue
        seen.add(key)
        results.append(
            Barcode(
                type=source_type,
                pk_format=pk_format,
                message=value,
                confidence=int(item.get("confidence") or 0),
            )
        )
    return results, warnings
