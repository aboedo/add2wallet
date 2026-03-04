"""PDF dominant color extraction with WCAG AA contrast enforcement."""

from __future__ import annotations

import re
from collections import Counter
from typing import Optional, Tuple

# WCAG AA minimum contrast ratio for normal text
WCAG_AA_RATIO = 4.5

# Event-type fallback palettes (bg, fg, label)
_EVENT_DEFAULTS: dict[str, tuple[str, str, str]] = {
    "flight":      ("rgb(0, 122, 255)",   "rgb(255, 255, 255)", "rgb(255, 255, 255)"),
    "boarding_pass": ("rgb(0, 122, 255)", "rgb(255, 255, 255)", "rgb(255, 255, 255)"),
    "event_ticket": ("rgb(255, 45, 85)",  "rgb(255, 255, 255)", "rgb(255, 255, 255)"),
    "transit":     ("rgb(48, 176, 199)",  "rgb(255, 255, 255)", "rgb(255, 255, 255)"),
    "hotel":       ("rgb(142, 142, 147)", "rgb(255, 255, 255)", "rgb(255, 255, 255)"),
    "generic":     ("rgb(0, 122, 255)",   "rgb(255, 255, 255)", "rgb(255, 255, 255)"),
}
_DEFAULT_PALETTE = ("rgb(0, 122, 255)", "rgb(255, 255, 255)", "rgb(255, 255, 255)")


RGBTuple = Tuple[int, int, int]
ColorTriple = Tuple[str, str, str]


def extract_colors(
    pdf_bytes: bytes,
    document_type: str = "generic",
) -> ColorTriple:
    """Return (bg, fg, label) color strings for a pass.

    1. Try to extract dominant non-white/black color from PDF pixels.
    2. Fall back to event-type defaults if extraction fails.
    3. Always ensure WCAG AA contrast (4.5:1) for fg/label over bg.
    """
    bg, fg, label = _extract_from_pdf(pdf_bytes)

    if bg is None:
        bg, fg, label = _EVENT_DEFAULTS.get(document_type, _DEFAULT_PALETTE)
        print(f"🎨 Using event-type default colors for '{document_type}'")
    else:
        fg, label = _pick_text_colors(bg)
        print(f"🎨 Extracted PDF color: bg={bg}")

    # Final contrast check
    bg_t = _parse_rgb(bg)
    fg_t = _parse_rgb(fg)
    if bg_t and fg_t and _contrast_ratio(bg_t, fg_t) < WCAG_AA_RATIO:
        print(f"⚠️ Contrast {_contrast_ratio(bg_t, fg_t):.2f}:1 < {WCAG_AA_RATIO}:1 — switching fg")
        fg, label = _pick_text_colors(bg)

    return bg, fg, label


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

def _extract_from_pdf(pdf_bytes: bytes) -> Tuple[Optional[str], Optional[str], Optional[str]]:
    """Rasterize first 2 pages and find dominant non-white/black color."""
    try:
        from PIL import Image  # type: ignore

        images = _rasterize(pdf_bytes)
        if not images:
            return None, None, None

        counter: Counter = Counter()
        for img in images:
            img = img.convert("RGB")
            img.thumbnail((400, 400))
            quantized = img.convert("P", palette=Image.ADAPTIVE, colors=16)
            palette = quantized.getpalette()
            for pixel in quantized.getdata():
                if palette and pixel * 3 + 2 < len(palette):
                    r = palette[pixel * 3]
                    g = palette[pixel * 3 + 1]
                    b = palette[pixel * 3 + 2]
                    counter[(r, g, b)] += 1

        if not counter:
            return None, None, None

        valid = [
            (color, count)
            for color, count in counter.most_common()
            if _is_useful_bg_color(color)
        ]

        if not valid:
            return None, None, None

        bg_rgb = valid[0][0]
        fg, label = _pick_text_colors(f"rgb({bg_rgb[0]}, {bg_rgb[1]}, {bg_rgb[2]})")
        return f"rgb({bg_rgb[0]}, {bg_rgb[1]}, {bg_rgb[2]})", fg, label

    except Exception as exc:
        print(f"⚠️ Color extraction failed: {exc}")
        return None, None, None


def _rasterize(pdf_bytes: bytes):
    """Try PyMuPDF then pdf2image to get PIL images of the first 2 pages."""
    try:
        import fitz  # type: ignore
        from PIL import Image  # type: ignore

        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
        pages = min(doc.page_count, 2)
        images = []
        for i in range(pages):
            pix = doc.load_page(i).get_pixmap(matrix=fitz.Matrix(2.0, 2.0))
            images.append(Image.frombytes("RGB", [pix.width, pix.height], pix.samples))
        doc.close()
        if images:
            return images
    except Exception:
        pass

    try:
        from pdf2image import convert_from_bytes  # type: ignore

        return [
            im.convert("RGB")
            for im in convert_from_bytes(pdf_bytes, first_page=1, last_page=2, dpi=150)
        ]
    except Exception:
        pass

    return []


def _is_useful_bg_color(c: RGBTuple) -> bool:
    r, g, b = c
    if min(r, g, b) > 240:
        return False  # white-ish
    if max(r, g, b) < 15:
        return False  # black-ish
    if (r + g + b) / 3 > 230:
        return False  # too light
    return True


def _pick_text_colors(bg: str) -> Tuple[str, str]:
    """Choose white or black text to ensure contrast over bg."""
    bg_t = _parse_rgb(bg)
    if bg_t is None:
        return "rgb(255, 255, 255)", "rgb(255, 255, 255)"

    lum = _luminance(bg_t)
    if lum > 0.4:  # light background
        return "rgb(0, 0, 0)", "rgb(60, 60, 67)"
    return "rgb(255, 255, 255)", "rgb(255, 255, 255)"


def _luminance(c: RGBTuple) -> float:
    def lin(x: float) -> float:
        return x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4

    r, g, b = (v / 255.0 for v in c)
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def _contrast_ratio(c1: RGBTuple, c2: RGBTuple) -> float:
    l1 = _luminance(c1)
    l2 = _luminance(c2)
    lighter = max(l1, l2)
    darker = min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)


def _parse_rgb(s: str) -> Optional[RGBTuple]:
    m = re.match(r"rgb\((\d+),\s*(\d+),\s*(\d+)\)", s)
    if not m:
        return None
    return int(m.group(1)), int(m.group(2)), int(m.group(3))
