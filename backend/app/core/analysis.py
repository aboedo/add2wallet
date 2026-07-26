from __future__ import annotations

import asyncio
import io
import logging
import math

from app.core.barcodes import BarcodeScanner
from app.core.config import Settings
from app.core.images import image_to_png_bytes
from app.core.metadata import MetadataExtractor
from app.core.models import AnalysisResult, DocumentKind, ValidatedUpload


logger = logging.getLogger(__name__)

MAX_TEXT_PAGES = 25
MAX_VISION_PAGES = 3
MAX_RENDER_PIXELS = 2_000_000


class DocumentAnalyzer:
    def __init__(
        self,
        settings: Settings,
        metadata_extractor: MetadataExtractor | None = None,
        barcode_scanner: BarcodeScanner | None = None,
    ) -> None:
        self.settings = settings
        self.metadata_extractor = metadata_extractor or MetadataExtractor(settings)
        self.barcode_scanner = barcode_scanner or BarcodeScanner()

    async def analyze(self, upload: ValidatedUpload) -> AnalysisResult:
        barcodes, warnings = await asyncio.to_thread(
            self.barcode_scanner.scan,
            upload.data,
            upload.kind,
            upload.filename,
        )
        barcode_messages = [barcode.message for barcode in barcodes]

        text = ""
        page_count = 1
        vision_images: list[tuple[bytes, str]] = []

        if upload.kind is DocumentKind.pdf:
            text, page_count = await asyncio.to_thread(_extract_pdf_text, upload.data)
            if not text.strip():
                vision_images = await asyncio.to_thread(_render_pdf_pages, upload.data)
        else:
            png_data = await asyncio.to_thread(image_to_png_bytes, upload.data, upload.kind)
            vision_images = [(png_data, "image/png")]
            text = await asyncio.to_thread(_try_image_text, png_data)

        if vision_images and (upload.kind is not DocumentKind.pdf or not text.strip()):
            metadata = await self.metadata_extractor.extract_from_vision(
                vision_images,
                upload.filename,
                barcode_messages,
                fallback_text=text,
            )
        else:
            metadata = await self.metadata_extractor.extract_from_text(text, upload.filename, barcode_messages)

        if barcode_messages and not metadata.barcode_data:
            metadata.barcode_data = barcode_messages[0]

        return AnalysisResult(
            text=text,
            page_count=page_count,
            metadata=metadata,
            barcodes=barcodes,
            warnings=warnings,
        )


def _extract_pdf_text(data: bytes) -> tuple[str, int]:
    try:
        import fitz

        doc = fitz.open(stream=data, filetype="pdf")
        page_count = doc.page_count
        parts = [doc.load_page(index).get_text() for index in range(min(page_count, MAX_TEXT_PAGES))]
        doc.close()
        return "\n".join(parts).strip(), max(page_count, 1)
    except Exception:
        logger.info("PyMuPDF text extraction failed", exc_info=True)

    try:
        import PyPDF2

        reader = PyPDF2.PdfReader(io.BytesIO(data))
        return "\n".join(page.extract_text() or "" for page in reader.pages).strip(), max(len(reader.pages), 1)
    except Exception:
        logger.info("PyPDF2 text extraction failed", exc_info=True)
        return "", 1


def _render_pdf_pages(data: bytes) -> list[tuple[bytes, str]]:
    images: list[tuple[bytes, str]] = []
    try:
        import fitz
        from PIL import Image

        doc = fitz.open(stream=data, filetype="pdf")
        for index in range(min(doc.page_count, MAX_VISION_PAGES)):
            page = doc.load_page(index)
            scale = _render_scale(page.rect.width, page.rect.height)
            pix = page.get_pixmap(matrix=fitz.Matrix(scale, scale), alpha=False)
            image = Image.frombytes("RGB", [pix.width, pix.height], pix.samples)
            buffer = io.BytesIO()
            image.save(buffer, format="PNG")
            images.append((buffer.getvalue(), "image/png"))
        doc.close()
    except Exception:
        logger.info("PDF vision rendering failed", exc_info=True)
    return images


def _render_scale(width: float, height: float) -> float:
    pixels_at_2x = max(width, 1) * max(height, 1) * 4
    if pixels_at_2x <= MAX_RENDER_PIXELS:
        return 2.0
    return max(0.5, min(2.0, math.sqrt(MAX_RENDER_PIXELS / (max(width, 1) * max(height, 1)))))


def _try_image_text(data: bytes) -> str:
    try:
        import pytesseract
        from PIL import Image

        return pytesseract.image_to_string(Image.open(io.BytesIO(data))).strip()
    except Exception:
        return ""


def _media_type(kind: DocumentKind) -> str:
    if kind is DocumentKind.png:
        return "image/png"
    if kind is DocumentKind.heic:
        return "image/png"
    return "image/jpeg"
