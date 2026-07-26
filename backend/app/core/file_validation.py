from __future__ import annotations

from app.core.config import Settings
from app.core.errors import FileTooLargeError, UnsupportedFileError
from app.core.images import load_upload_image
from app.core.models import DocumentKind, ValidatedUpload
from app.services.pdf_validator import PDFValidator


HEIC_BRANDS = {
    b"heic",
    b"heix",
    b"hevc",
    b"hevx",
    b"heim",
    b"heis",
    b"hevm",
    b"hevs",
    b"mif1",
    b"msf1",
    b"heif",
}

MIME_TYPES_BY_KIND = {
    DocumentKind.pdf: {"application/pdf", "application/x-pdf"},
    DocumentKind.jpeg: {"image/jpeg", "image/jpg", "image/pjpeg"},
    DocumentKind.png: {"image/png"},
    DocumentKind.heic: {"image/heic", "image/heif", "image/heic-sequence", "image/heif-sequence"},
}
GENERIC_MIME_TYPES = {"application/octet-stream", "binary/octet-stream"}


def validate_upload(filename: str | None, content_type: str | None, data: bytes, settings: Settings) -> ValidatedUpload:
    if not data:
        raise UnsupportedFileError("Uploaded file is empty")
    if len(data) > settings.max_upload_bytes:
        raise FileTooLargeError(settings.max_upload_bytes)

    kind = sniff_document_kind(data)
    if kind is None:
        raise UnsupportedFileError("Unsupported file type. Upload a PDF, JPEG, PNG, HEIC, or HEIF file.")
    _validate_declared_mime(kind, content_type)
    _validate_payload(kind, data)

    extension = {
        DocumentKind.pdf: "pdf",
        DocumentKind.jpeg: "jpg",
        DocumentKind.png: "png",
        DocumentKind.heic: "heic",
    }[kind]
    return ValidatedUpload(
        filename=filename or f"upload.{extension}",
        content_type=content_type,
        kind=kind,
        data=data,
        extension=extension,
    )


def sniff_document_kind(data: bytes) -> DocumentKind | None:
    if data.startswith(b"%PDF-"):
        return DocumentKind.pdf
    if data.startswith(b"\xff\xd8\xff"):
        return DocumentKind.jpeg
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return DocumentKind.png
    if _is_heic(data):
        return DocumentKind.heic
    return None


def _is_heic(data: bytes) -> bool:
    if len(data) < 12 or data[4:8] != b"ftyp":
        return False
    major = data[8:12]
    compatible = [data[i : i + 4] for i in range(16, min(len(data), 64), 4)]
    return major in HEIC_BRANDS or any(brand in HEIC_BRANDS for brand in compatible)


def _validate_declared_mime(kind: DocumentKind, content_type: str | None) -> None:
    declared = (content_type or "").split(";", 1)[0].strip().lower()
    if not declared or declared in GENERIC_MIME_TYPES:
        return
    if declared not in MIME_TYPES_BY_KIND[kind]:
        raise UnsupportedFileError("File content does not match declared MIME type")


def _validate_payload(kind: DocumentKind, data: bytes) -> None:
    if kind is DocumentKind.pdf:
        valid, error = PDFValidator().validate(data)
        if not valid:
            raise UnsupportedFileError(f"Invalid PDF: {error}")
        return

    if kind in {DocumentKind.jpeg, DocumentKind.png, DocumentKind.heic}:
        load_upload_image(data, kind)
