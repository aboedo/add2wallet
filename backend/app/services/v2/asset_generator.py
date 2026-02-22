"""Generate per-pass icon and thumbnail assets."""

from __future__ import annotations

import os
import re
from typing import Optional, Tuple

RGBTuple = Tuple[int, int, int]


def generate_assets(
    pass_dir: str,
    pdf_bytes: Optional[bytes],
    document_type: str,
    title: str,
    bg_color: str,
    fg_color: str,
    assets_path: Optional[str] = None,
) -> None:
    """Write icon.png, icon@2x.png, icon@3x.png (and optionally thumbnail.png)
    into *pass_dir*.

    Falls back to static icons from *assets_path* if dynamic generation fails.
    """
    try:
        _generate_dynamic(pass_dir, pdf_bytes, document_type, title, bg_color, fg_color)
    except Exception as exc:
        print(f"⚠️ Dynamic asset generation failed: {exc} — using static icons")
        _copy_static(pass_dir, assets_path)


# ---------------------------------------------------------------------------
# Dynamic generation
# ---------------------------------------------------------------------------

def _generate_dynamic(
    pass_dir: str,
    pdf_bytes: Optional[bytes],
    document_type: str,
    title: str,
    bg_color: str,
    fg_color: str,
) -> None:
    from PIL import Image, ImageDraw, ImageFont  # type: ignore

    bg = _parse_rgb(bg_color) or (0, 122, 255)
    fg = _parse_rgb(fg_color) or (255, 255, 255)
    abbrev = _abbreviation(document_type, title)

    # Icons at 1×, 2×, 3× (29 pt → 29 / 58 / 87 px)
    icon_sizes = [(29, "icon.png"), (58, "icon@2x.png"), (87, "icon@3x.png")]
    for size, name in icon_sizes:
        img = Image.new("RGB", (size, size), bg)
        draw = ImageDraw.Draw(img)
        font_size = max(10, int(size * 0.42))
        try:
            font = ImageFont.truetype("Arial.ttf", font_size)
        except Exception:
            font = ImageFont.load_default()
        bbox = draw.textbbox((0, 0), abbrev, font=font)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        draw.text(((size - tw) / 2, (size - th) / 2), abbrev, fill=fg, font=font)
        img.save(os.path.join(pass_dir, name), format="PNG")

    # Thumbnail from first PDF page
    if pdf_bytes:
        thumb = _render_thumbnail(pdf_bytes)
        if thumb is not None:
            thumb.thumbnail((180, 180))
            thumb.save(os.path.join(pass_dir, "thumbnail.png"), format="PNG")
            print("🖼️ Generated thumbnail from PDF")


def _render_thumbnail(pdf_bytes: bytes):
    try:
        import fitz  # type: ignore
        from PIL import Image  # type: ignore

        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
        if doc.page_count:
            pix = doc.load_page(0).get_pixmap(matrix=fitz.Matrix(1.5, 1.5))
            return Image.frombytes("RGB", [pix.width, pix.height], pix.samples)
        doc.close()
    except Exception:
        pass

    try:
        from pdf2image import convert_from_bytes  # type: ignore

        pages = convert_from_bytes(pdf_bytes, first_page=1, last_page=1)
        if pages:
            return pages[0].convert("RGB")
    except Exception:
        pass

    return None


def _abbreviation(document_type: str, title: str) -> str:
    dt = document_type.lower()
    t = title.lower()
    if "flight" in dt or "boarding" in dt or "air" in t:
        return "FLY"
    if "transit" in dt or "train" in t or "rail" in t:
        return "RAIL"
    if "hotel" in dt:
        return "HTL"
    if "event_ticket" in dt or "concert" in t or "music" in t or "show" in t:
        return "MUS"
    if "sport" in t or "stadium" in t:
        return "SPT"
    if "movie" in t or "theater" in t:
        return "MOV"
    return "TKT"


# ---------------------------------------------------------------------------
# Static fallback
# ---------------------------------------------------------------------------

def _copy_static(pass_dir: str, assets_path: Optional[str]) -> None:
    import shutil

    if assets_path is None:
        assets_path = os.path.join(os.path.dirname(__file__), "../../../assets")

    for name in ["icon.png", "icon@2x.png", "icon@3x.png"]:
        src = os.path.join(assets_path, name)
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(pass_dir, name))
        else:
            print(f"⚠️ Static icon not found: {src}")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _parse_rgb(s: str) -> Optional[RGBTuple]:
    m = re.match(r"rgb\((\d+),\s*(\d+),\s*(\d+)\)", s)
    if not m:
        return None
    return int(m.group(1)), int(m.group(2)), int(m.group(3))
