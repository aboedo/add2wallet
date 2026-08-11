from __future__ import annotations

import asyncio
import io
import logging
import math

from app.core.barcodes import BarcodeScanner
from app.core.config import Settings
from app.core.file_validation import validate_upload
from app.core.images import image_to_png_bytes
from app.core.metadata import MetadataExtractor
from app.core.models import (
    AnalysisResult,
    ClassifiedDocument,
    DocumentKind,
    ExtractedDocument,
    PassArtifact,
    StructuredMetadata,
    ValidatedUpload,
)
from app.core.pass_builder import WalletPassBuilder


logger = logging.getLogger(__name__)

MAX_TEXT_PAGES = 25
MAX_VISION_PAGES = 3
MAX_RENDER_PIXELS = 2_000_000


class IngestStage:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def run(self, filename: str | None, content_type: str | None, data: bytes) -> ValidatedUpload:
        return validate_upload(filename, content_type, data, self.settings)


class ExtractionStage:
    def __init__(self, barcode_scanner: BarcodeScanner | None = None) -> None:
        self.barcode_scanner = barcode_scanner or BarcodeScanner()

    async def run(self, upload: ValidatedUpload) -> ExtractedDocument:
        barcodes, warnings = await asyncio.to_thread(
            self.barcode_scanner.scan,
            upload.data,
            upload.kind,
            upload.filename,
        )

        if upload.kind is DocumentKind.pdf:
            pages, page_count = await asyncio.to_thread(_extract_pdf_pages, upload.data)
            text = "\n".join(pages).strip()
            vision_images = []
            if not text.strip():
                vision_images = await asyncio.to_thread(_render_pdf_pages, upload.data)
            return ExtractedDocument(
                text=text,
                page_count=page_count,
                pages=pages,
                vision_images=vision_images,
                barcodes=barcodes,
                warnings=warnings,
            )

        png_data = await asyncio.to_thread(image_to_png_bytes, upload.data, upload.kind)
        image_text = await asyncio.to_thread(_try_image_text, png_data)
        return ExtractedDocument(
            text=image_text,
            page_count=1,
            vision_images=[(png_data, "image/png")],
            barcodes=barcodes,
            warnings=warnings,
        )


class ClassificationStage:
    def __init__(self, settings: Settings, metadata_extractor: MetadataExtractor | None = None) -> None:
        self.settings = settings
        self.metadata_extractor = metadata_extractor or MetadataExtractor(settings)

    async def run(self, upload: ValidatedUpload, extracted: ExtractedDocument) -> ClassifiedDocument:
        barcode_messages = [barcode.message for barcode in extracted.barcodes]
        if extracted.vision_images and (upload.kind is not DocumentKind.pdf or not extracted.text.strip()):
            metadata_task = self.metadata_extractor.extract_from_vision(
                extracted.vision_images,
                upload.filename,
                barcode_messages,
                fallback_text=extracted.text,
            )
        else:
            metadata_task = self.metadata_extractor.extract_from_text(
                extracted.text,
                upload.filename,
                barcode_messages,
            )

        # Segment extraction is independent of the document-level pass — run
        # both together so a multi-leg document costs one round trip, not two.
        metadata, (segments, group_id, group_name) = await asyncio.gather(
            metadata_task,
            self.metadata_extractor.extract_segments(extracted.pages, upload.filename),
        )

        barcodes = _consolidate_barcodes(extracted.barcodes, metadata)
        if barcode_messages and not metadata.barcode_data:
            metadata.barcode_data = barcode_messages[0]

        return ClassifiedDocument(
            metadata=metadata,
            barcodes=barcodes,
            warnings=extracted.warnings,
            segments=segments,
            group_id=group_id or metadata.confirmation_number,
            # Segment extraction only runs on documents with two or more pages
            # of text, so a single page holding four tickets never reached it.
            # The document-level pass sees every one of those documents.
            group_name=group_name or metadata.group_name,
        )


class EnrichmentStage:
    def run(self, upload: ValidatedUpload, extracted: ExtractedDocument, classified: ClassifiedDocument) -> AnalysisResult:
        metadata = classified.metadata.model_copy(deep=True)
        _apply_derived_colors(upload, metadata)
        return AnalysisResult(
            text=extracted.text,
            page_count=extracted.page_count,
            metadata=metadata,
            barcodes=classified.barcodes,
            warnings=classified.warnings,
            segments=classified.segments,
            group_id=classified.group_id,
            group_name=classified.group_name,
        )


class PassGenerationStage:
    def __init__(self, settings: Settings, pass_builder: WalletPassBuilder | None = None) -> None:
        self.pass_builder = pass_builder or WalletPassBuilder(settings)

    async def run(self, upload: ValidatedUpload, analysis: AnalysisResult) -> list[PassArtifact]:
        return await asyncio.to_thread(self.pass_builder.build, upload, analysis)


def _consolidate_barcodes(barcodes: list, metadata: StructuredMetadata) -> list:
    if not barcodes:
        return []

    real_barcodes = [
        barcode
        for barcode in barcodes
        if not barcode.message.lower().startswith(("http://", "https://"))
    ] or barcodes

    # Codes sitting on different pages are different legs of the same journey,
    # never duplicates of one ticket — keep every one regardless of what the
    # model said about multiple_tickets.
    pages = {barcode.page for barcode in real_barcodes if barcode.page is not None}
    if metadata.multiple_tickets or len(pages) > 1:
        return real_barcodes

    def score(barcode) -> tuple[int, int, int]:
        priority = {
            "PDF417": 5,
            "AZTEC": 4,
            "QRCODE": 3,
            "QR_CODE": 3,
            "CODE128": 2,
            "CODE39": 2,
        }.get(barcode.type.upper(), 1)
        return (priority, barcode.confidence, len(barcode.message))

    return [max(real_barcodes, key=score)]


def _apply_derived_colors(upload: ValidatedUpload, metadata: StructuredMetadata) -> None:
    is_pdf = upload.kind is DocumentKind.pdf
    # Pixel extraction only understands PDFs. For a screenshot we still want the
    # brand colour, but with nothing to add we leave the model's own answer be.
    if not is_pdf and not metadata.brand_color:
        return
    try:
        from app.services.v2.color_extractor import extract_colors

        pdf_bytes = upload.data if is_pdf else b""
        bg_color, fg_color, label_color = extract_colors(
            pdf_bytes,
            metadata.event_type,
            brand_color=metadata.brand_color,
        )
        metadata.background_color = bg_color or metadata.background_color
        metadata.foreground_color = fg_color or metadata.foreground_color
        metadata.label_color = label_color or metadata.label_color
    except Exception:
        logger.info("Color enrichment failed; keeping metadata colors", exc_info=True)


def _extract_pdf_text(data: bytes) -> tuple[str, int]:
    pages, page_count = _extract_pdf_pages(data)
    return "\n".join(pages).strip(), page_count


def _extract_pdf_pages(data: bytes) -> tuple[list[str], int]:
    """Per-page text. Page boundaries are what let a leg be tied to its barcode."""
    try:
        import fitz

        doc = fitz.open(stream=data, filetype="pdf")
        page_count = doc.page_count
        parts = [doc.load_page(index).get_text() for index in range(min(page_count, MAX_TEXT_PAGES))]
        doc.close()
        return parts, max(page_count, 1)
    except Exception:
        logger.info("PyMuPDF text extraction failed", exc_info=True)

    try:
        import PyPDF2

        reader = PyPDF2.PdfReader(io.BytesIO(data))
        return [page.extract_text() or "" for page in reader.pages], max(len(reader.pages), 1)
    except Exception:
        logger.info("PyPDF2 text extraction failed", exc_info=True)
        return [], 1


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
