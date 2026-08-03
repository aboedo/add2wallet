"""Colour selection: brand colour first, saturated pixels next, always AA."""

import pytest

from app.services.v2.color_extractor import (
    MIN_SATURATION,
    WCAG_AA_RATIO,
    _contrast_ratio,
    _is_useful_bg_color,
    _normalize_brand_color,
    _parse_rgb,
    _saturation,
    extract_colors,
)
from app.core.models import DocumentKind, StructuredMetadata, ValidatedUpload
from app.core.stages import _apply_derived_colors
from app.services.v2.models import PDFExtraction

WHITE = (255, 255, 255)
BLACK = (0, 0, 0)


class TestGreyRejection:
    """The bug: a ticket is mostly white paper, so grey used to win by count."""

    @pytest.mark.parametrize(
        "grey",
        [(149, 149, 150), (217, 217, 217), (169, 169, 169), (211, 215, 219), (136, 120, 109)],
    )
    def test_observed_greys_are_rejected(self, grey):
        assert not _is_useful_bg_color(grey)

    @pytest.mark.parametrize("color", [(0, 43, 0), (11, 27, 63), (0, 102, 246), (74, 24, 18)])
    def test_real_brand_colors_are_kept(self, color):
        assert _is_useful_bg_color(color)

    def test_saturation_is_zero_for_any_grey(self):
        assert _saturation((128, 128, 128)) == 0.0
        assert _saturation((255, 0, 0)) == 1.0


class TestBrandColorNormalization:
    @pytest.mark.parametrize(
        "raw,expected",
        [
            ("#a50034", "rgb(165, 0, 52)"),
            ("a50034", "rgb(165, 0, 52)"),
            ("#F00", "rgb(255, 0, 0)"),
            ("  #0B1B3F  ", "rgb(11, 27, 63)"),
        ],
    )
    def test_accepts_hex_forms(self, raw, expected):
        assert _normalize_brand_color(raw) == expected

    @pytest.mark.parametrize("raw", [None, "", "blue", "#12345", "#gggggg"])
    def test_rejects_malformed(self, raw):
        assert _normalize_brand_color(raw) is None

    @pytest.mark.parametrize("raw", ["#c0c0c0", "#ffffff", "#f5f5f5", "#808080"])
    def test_rejects_washed_out_answers(self, raw):
        """A model that answers grey must not put us back where we started."""
        assert _normalize_brand_color(raw) is None


class TestExtractColors:
    def test_brand_color_wins_over_pixels(self):
        bg, _, _ = extract_colors(b"not a pdf", "event_ticket", brand_color="#a50034")
        assert bg == "rgb(165, 0, 52)"

    @pytest.mark.parametrize(
        "document_type",
        ["flight", "boarding_pass", "event_ticket", "transit", "hotel", "generic"],
    )
    def test_every_event_default_is_a_real_colour(self, document_type):
        """No fallback may be grey — that was the whole complaint."""
        bg, fg, label = extract_colors(b"not a pdf", document_type)
        assert _saturation(_parse_rgb(bg)) >= MIN_SATURATION
        for text in (fg, label):
            assert _contrast_ratio(_parse_rgb(bg), _parse_rgb(text)) >= WCAG_AA_RATIO

    def test_unknown_document_type_still_returns_a_palette(self):
        bg, _, _ = extract_colors(b"not a pdf", "no_such_type")
        assert _parse_rgb(bg) is not None

    @pytest.mark.parametrize(
        "brand",
        ["#a50034", "#ff2d55", "#ffcc00", "#0066f6", "#002b00", "#e60000", "#14d0c8"],
    )
    def test_result_always_clears_wcag_aa(self, brand):
        bg, fg, label = extract_colors(b"not a pdf", "event_ticket", brand_color=brand)
        for text in (fg, label):
            ratio = _contrast_ratio(_parse_rgb(bg), _parse_rgb(text))
            assert ratio >= WCAG_AA_RATIO, f"{brand}: {text} on {bg} is only {ratio:.2f}:1"

    def test_light_brand_color_keeps_its_lightness_and_gets_black_text(self):
        bg, fg, _ = extract_colors(b"not a pdf", "event_ticket", brand_color="#ffcc00")
        assert bg == "rgb(255, 204, 0)"
        assert fg == "rgb(0, 0, 0)"

    def test_mid_brand_color_is_deepened_to_carry_white_text(self):
        """#ff2d55 can't hold white text at 4.5:1, so the hue is deepened."""
        bg, fg, _ = extract_colors(b"not a pdf", "event_ticket", brand_color="#ff2d55")
        assert fg == "rgb(255, 255, 255)"
        r, g, b = _parse_rgb(bg)
        assert r < 255, "background should have been darkened"
        assert r > g and r > b, "hue should survive the darkening"


class TestDerivedColorsStage:
    """The stage that actually runs in production (app/core/pipeline.py)."""

    @staticmethod
    def _upload(kind=DocumentKind.pdf, data=b"not a pdf"):
        return ValidatedUpload(
            filename="ticket.pdf", content_type=None, kind=kind, data=data, extension="pdf"
        )

    def test_brand_color_reaches_the_pass_background(self):
        metadata = StructuredMetadata(event_type="event_ticket", brand_color="#a50034")
        _apply_derived_colors(self._upload(), metadata)
        assert metadata.background_color == "rgb(165, 0, 52)"
        assert metadata.foreground_color == "rgb(255, 255, 255)"

    def test_grey_brand_color_does_not_reach_the_pass(self):
        metadata = StructuredMetadata(event_type="event_ticket", brand_color="#c0c0c0")
        _apply_derived_colors(self._upload(), metadata)
        assert _saturation(_parse_rgb(metadata.background_color)) >= MIN_SATURATION

    def test_image_upload_still_gets_its_brand_color(self):
        """Screenshots skipped colour derivation entirely before."""
        metadata = StructuredMetadata(event_type="event_ticket", brand_color="#005eb8")
        _apply_derived_colors(self._upload(kind=DocumentKind.png), metadata)
        assert metadata.background_color == "rgb(0, 94, 184)"

    def test_image_without_brand_color_keeps_model_colors(self):
        metadata = StructuredMetadata(event_type="event_ticket")
        original = metadata.background_color
        _apply_derived_colors(self._upload(kind=DocumentKind.png), metadata)
        assert metadata.background_color == original


class TestBrandColorField:
    @pytest.mark.parametrize(
        "raw,expected",
        [("#A50034", "#a50034"), ("a50034", "#a50034"), ("#f00", "#ff0000")],
    )
    def test_model_normalizes_hex(self, raw, expected):
        extraction = PDFExtraction(
            document_type="event_ticket", title="T", confidence=90, brand_color=raw
        )
        assert extraction.brand_color == expected

    @pytest.mark.parametrize("raw", ["dark red", "rgb(1,2,3)", "", None])
    def test_model_drops_non_hex(self, raw):
        extraction = PDFExtraction(
            document_type="event_ticket", title="T", confidence=90, brand_color=raw
        )
        assert extraction.brand_color is None

    def test_brand_color_defaults_to_none(self):
        extraction = PDFExtraction(document_type="generic", title="T", confidence=50)
        assert extraction.brand_color is None
