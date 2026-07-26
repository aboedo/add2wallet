"""Per-leg passes for multi-part documents.

A "Norway in a Nutshell" itinerary is five legs across five pages. Extracting
only document-level metadata produced N near-identical passes; these tests pin
the behaviour that gives each pass its own leg.
"""

import pytest

from app.core.barcodes import _normalize
from app.core.metadata import _humanize
from app.core.models import AnalysisResult, Barcode, PassSegment, StructuredMetadata
from app.core.pass_builder import _description, _merge_segment, _segment_for, _structure
from app.core.stages import _consolidate_barcodes


def _segment(page, origin, destination, **overrides):
    base = dict(
        page=page,
        label=f"Train {origin} to {destination}",
        origin=origin,
        destination=destination,
        depart_date="2026-08-18",
        depart_time="08:29",
        arrive_date="2026-08-18",
        arrive_time="09:41",
        carrier="Vy",
        seat_info="Car 1, Seats 9 and 10",
        confirmation_number="#YBX5YXF2",
    )
    base.update(overrides)
    return PassSegment(**base)


def _analysis(segments, barcodes):
    return AnalysisResult(
        metadata=StructuredMetadata(title="Train & Bus Tickets", multiple_tickets=True),
        barcodes=barcodes,
        segments=segments,
        group_id="Q9TMU7",
        group_name="Norway in a Nutshell",
    )


def _barcode(page):
    return Barcode(type="QRCODE", pk_format="PKBarcodeFormatQR", message=f"code-{page}", page=page)


# --------------------------------------------------------------------------
# Matching a pass to its leg
# --------------------------------------------------------------------------

def test_segment_is_matched_by_the_page_its_barcode_came_from():
    segments = [_segment(0, "Bergen", "Voss"), _segment(3, "Flåm", "Myrdal")]
    analysis = _analysis(segments, [_barcode(3), _barcode(0)])

    # Barcode order does not follow page order — the page is what decides.
    assert _segment_for(analysis, analysis.barcodes[0], 0).origin == "Flåm"
    assert _segment_for(analysis, analysis.barcodes[1], 1).origin == "Bergen"


def test_two_passengers_on_one_leg_get_the_same_segment():
    segments = [_segment(0, "Bergen", "Voss")]
    analysis = _analysis(segments, [_barcode(0), _barcode(0)])

    assert _segment_for(analysis, analysis.barcodes[0], 0) is _segment_for(
        analysis, analysis.barcodes[1], 1
    )


def test_falls_back_to_position_when_the_barcode_has_no_page():
    segments = [_segment(0, "Bergen", "Voss"), _segment(1, "Voss", "Gudvangen")]
    analysis = _analysis(segments, [])

    assert _segment_for(analysis, None, 1).origin == "Voss"


def test_no_segments_means_no_per_leg_data():
    analysis = _analysis([], [_barcode(0)])

    assert _segment_for(analysis, analysis.barcodes[0], 0) is None


# --------------------------------------------------------------------------
# Page numbering — detectors disagreed, which mis-assigned every leg
# --------------------------------------------------------------------------

def test_detector_pages_are_normalized_to_zero_based():
    """zxing reported 0-based pages while every other path reported 1-based."""
    barcodes, _ = _normalize([{"type": "QRCODE", "data": "x", "page": 1}])

    assert barcodes[0].page == 0


def test_missing_or_invalid_page_stays_unset():
    barcodes, _ = _normalize(
        [{"type": "QRCODE", "data": "a"}, {"type": "QRCODE", "data": "b", "page": 0}]
    )

    assert barcodes[0].page is None
    assert barcodes[1].page is None


# --------------------------------------------------------------------------
# Keeping every leg's code
# --------------------------------------------------------------------------

def test_codes_on_different_pages_are_never_collapsed():
    """They are separate legs, not duplicate scans of one ticket."""
    barcodes = [_barcode(0), _barcode(1), _barcode(2)]

    kept = _consolidate_barcodes(barcodes, StructuredMetadata(title="Trip"))

    assert len(kept) == 3


def test_codes_on_a_single_page_still_collapse_to_the_best_one():
    barcodes = [
        Barcode(type="QRCODE", pk_format="PKBarcodeFormatQR", message="qr", page=0),
        Barcode(type="PDF417", pk_format="PKBarcodeFormatPDF417", message="pdf417", page=0),
    ]

    kept = _consolidate_barcodes(barcodes, StructuredMetadata(title="Ticket"))

    assert [b.type for b in kept] == ["PDF417"]


# --------------------------------------------------------------------------
# What the leg puts on the pass
# --------------------------------------------------------------------------

def test_segment_overrides_document_level_metadata():
    merged = _merge_segment(
        StructuredMetadata(title="Train & Bus Tickets", date="2026-08-18", seat_info="ignored"),
        _segment(0, "Bergen", "Voss"),
    )

    assert merged.title == "Train Bergen to Voss"
    assert merged.seat_info == "Car 1, Seats 9 and 10"
    assert merged.confirmation_number == "#YBX5YXF2"
    assert merged.organizer == "Vy"


def test_leg_pass_leads_with_the_route_and_both_times():
    structure = _structure(StructuredMetadata(title="Trip"), _segment(0, "Bergen", "Voss"))

    assert structure.primaryFields[0].value == "Bergen → Voss"
    values = {f.key: f.value for f in structure.secondaryFields}
    assert "08:29" in values["depart"]
    assert "09:41" in values["arrive"]
    assert values["seat"] == "Car 1, Seats 9 and 10"


def test_leg_pass_carries_the_booking_group_on_the_back():
    analysis = _analysis([_segment(0, "Bergen", "Voss")], [_barcode(0)])

    back = {f.key: f.value for f in _structure(StructuredMetadata(title="Trip"), analysis.segments[0], analysis).backFields}

    assert back["order"] == "Q9TMU7"
    assert back["trip"] == "Norway in a Nutshell"


def test_description_describes_the_leg_not_the_document():
    description = _description(StructuredMetadata(title="Trip"), _segment(0, "Bergen", "Voss"))

    assert "Bergen → Voss" in description


def test_document_without_segments_keeps_the_plain_layout():
    structure = _structure(StructuredMetadata(title="Concert", date="2026-08-13", time="20:00"))

    assert structure.primaryFields[0].value == "Concert"
    assert {f.label for f in structure.secondaryFields} == {"Date", "Time"}


# --------------------------------------------------------------------------
# Structured values must never reach the user as raw Python
# --------------------------------------------------------------------------

@pytest.mark.parametrize(
    ("value", "expected"),
    [
        ({"car": 1, "seats": [9, 10]}, "Car 1, Seats 9, 10"),
        ({"car": 4, "seats": [11], "empty": None}, "Car 4, Seats 11"),
        ([9, 10], "9, 10"),
        (True, "Yes"),
        (7, "7"),
    ],
)
def test_structured_values_render_as_readable_text(value, expected):
    """seat_info came back as a dict and leaked "{'car': 1, 'seats': [9, 10]}"."""
    assert _humanize(value) == expected
