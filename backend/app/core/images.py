from __future__ import annotations

import io

from PIL import Image, ImageOps

from app.core.errors import UnsupportedFileError
from app.core.models import DocumentKind


def load_upload_image(data: bytes, kind: DocumentKind) -> Image.Image:
    """Decode an uploaded image into an RGB PIL image with orientation applied."""
    try:
        if kind is DocumentKind.heic:
            try:
                import pillow_heif
            except ImportError as exc:
                raise UnsupportedFileError("HEIC support is not available in this runtime") from exc

            pillow_heif.register_heif_opener()

        with Image.open(io.BytesIO(data)) as image:
            image.load()
            return ImageOps.exif_transpose(image).convert("RGB")
    except UnsupportedFileError:
        raise
    except Exception as exc:
        raise UnsupportedFileError("Invalid image file") from exc


def image_to_png_bytes(data: bytes, kind: DocumentKind) -> bytes:
    image = load_upload_image(data, kind)
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()
