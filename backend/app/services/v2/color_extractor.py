"""PDF dominant color extraction with WCAG AA contrast enforcement."""

from __future__ import annotations

import re
from collections import Counter
from typing import Optional, Tuple

# WCAG AA minimum contrast ratio for normal text
WCAG_AA_RATIO = 4.5

# Minimum HSV saturation for a colour to read as a deliberate brand colour
# rather than paper, ink or antialiasing grey.
MIN_SATURATION = 0.25

# How far we're willing to deepen a background so white text clears AA
_DARKEN_STEP = 0.1
_MAX_DARKEN_STEPS = 7

# Above this relative luminance a background is treated as light, and gets
# black text rather than being deepened to carry white text.
_LIGHT_BG_LUMINANCE = 0.4

_WHITE = (255, 255, 255)
_BLACK = (0, 0, 0)

# Event-type fallback palettes (bg, fg, label)
_EVENT_DEFAULTS: dict[str, tuple[str, str, str]] = {
    "flight":      ("rgb(0, 122, 255)",   "rgb(255, 255, 255)", "rgb(255, 255, 255)"),
    "boarding_pass": ("rgb(0, 122, 255)", "rgb(255, 255, 255)", "rgb(255, 255, 255)"),
    "event_ticket": ("rgb(255, 45, 85)",  "rgb(255, 255, 255)", "rgb(255, 255, 255)"),
    "transit":     ("rgb(48, 176, 199)",  "rgb(255, 255, 255)", "rgb(255, 255, 255)"),
    "hotel":       ("rgb(88, 86, 214)",   "rgb(255, 255, 255)", "rgb(255, 255, 255)"),
    "generic":     ("rgb(0, 122, 255)",   "rgb(255, 255, 255)", "rgb(255, 255, 255)"),
}
_DEFAULT_PALETTE = ("rgb(0, 122, 255)", "rgb(255, 255, 255)", "rgb(255, 255, 255)")


RGBTuple = Tuple[int, int, int]
ColorTriple = Tuple[str, str, str]


def extract_colors(
    pdf_bytes: bytes,
    document_type: str = "generic",
    brand_color: Optional[str] = None,
) -> ColorTriple:
    """Return (bg, fg, label) color strings for a pass.

    1. Use the brand colour the AI inferred from the document, if there is one.
       It knows a football club's kit colour; pixel counting never will.
    2. Otherwise take the dominant *saturated* colour out of the PDF pixels.
    3. Otherwise fall back to event-type defaults.
    4. Always ensure WCAG AA contrast (4.5:1) for fg/label over bg.
    """
    bg = _normalize_brand_color(brand_color)

    if bg is not None:
        print(f"🎨 Using AI brand color: bg={bg}")
    else:
        bg, _, _ = _extract_from_pdf(pdf_bytes)
        if bg is not None:
            print(f"🎨 Extracted PDF color: bg={bg}")

    if bg is None:
        bg, _, _ = _EVENT_DEFAULTS.get(document_type, _DEFAULT_PALETTE)
        print(f"🎨 Using event-type default colors for '{document_type}'")

    bg_t = _parse_rgb(bg) or _parse_rgb(_DEFAULT_PALETTE[0])
    return _ensure_contrast(bg_t)  # type: ignore[arg-type]


def _ensure_contrast(bg: RGBTuple) -> ColorTriple:
    """Return a (bg, fg, label) triple that actually clears WCAG AA.

    Light backgrounds keep black text. Everything else aims for white text and
    deepens the background — same hue, more punch — until white clears 4.5:1.
    """
    # Genuinely pale backgrounds (a yellow, a bright cyan) belong with black
    # text — darkening them enough for white would throw the brand colour away.
    if _luminance(bg) > _LIGHT_BG_LUMINANCE and _contrast_ratio(bg, _BLACK) >= WCAG_AA_RATIO:
        return _fmt(bg), "rgb(0, 0, 0)", "rgb(60, 60, 67)"

    darkened = bg
    for step in range(_MAX_DARKEN_STEPS + 1):
        candidate = _scale(bg, 1.0 - step * _DARKEN_STEP)
        darkened = candidate
        if _contrast_ratio(candidate, _WHITE) >= WCAG_AA_RATIO:
            if step:
                print(f"🎨 Deepened bg {_fmt(bg)} → {_fmt(candidate)} for AA contrast")
            return _fmt(candidate), "rgb(255, 255, 255)", "rgb(255, 255, 255)"

    print(f"⚠️ Could not reach {WCAG_AA_RATIO}:1 for {_fmt(bg)} — using darkest variant")
    return _fmt(darkened), "rgb(255, 255, 255)", "rgb(255, 255, 255)"


def _scale(c: RGBTuple, factor: float) -> RGBTuple:
    return tuple(max(0, min(255, round(v * factor))) for v in c)  # type: ignore[return-value]


def _fmt(c: RGBTuple) -> str:
    return f"rgb({c[0]}, {c[1]}, {c[2]})"


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
            for pixel in quantized.get_flattened_data():
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

        # A logo covers far fewer pixels than a tinted background, so weight
        # frequency by how vivid the colour is instead of taking the raw winner.
        bg_rgb = max(valid, key=lambda item: item[1] * (0.5 + _saturation(item[0])))[0]
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


def _normalize_brand_color(brand_color: Optional[str]) -> Optional[str]:
    """Turn a brand colour into our 'rgb(r, g, b)' form.

    Accepts '#RRGGBB', '#RGB', bare hex and 'rgb(r, g, b)' — models answer in
    all of them. Rejects greys and near-white/near-black the same way pixel
    colours are rejected, so a lazy answer can't put us back where we started.
    """
    if not brand_color:
        return None

    rgb = _parse_rgb(brand_color.strip())
    if rgb is None:
        candidate = brand_color.strip().lstrip("#")
        if len(candidate) == 3:
            candidate = "".join(ch * 2 for ch in candidate)
        if not re.fullmatch(r"[0-9a-fA-F]{6}", candidate):
            print(f"⚠️ Ignoring malformed brand color: {brand_color!r}")
            return None
        rgb = tuple(int(candidate[i:i + 2], 16) for i in range(0, 6, 2))  # type: ignore[assignment]

    if not _is_useful_bg_color(rgb):  # type: ignore[arg-type]
        print(f"⚠️ Ignoring washed-out brand color: {brand_color!r}")
        return None

    return f"rgb({rgb[0]}, {rgb[1]}, {rgb[2]})"


def _saturation(c: RGBTuple) -> float:
    """HSV saturation — 0 for any shade of grey, 1 for a pure hue."""
    mx = max(c)
    if mx == 0:
        return 0.0
    return (mx - min(c)) / mx


def _is_useful_bg_color(c: RGBTuple) -> bool:
    r, g, b = c
    if min(r, g, b) > 240:
        return False  # white-ish
    if max(r, g, b) < 15:
        return False  # black-ish
    if (r + g + b) / 3 > 230:
        return False  # too light
    # A ticket is mostly white paper and black text, so the most *frequent*
    # colour is the grey of antialiased glyphs. Insist on real chroma.
    if _saturation(c) < MIN_SATURATION:
        return False
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
