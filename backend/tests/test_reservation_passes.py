"""Passes for documents without a barcode (hotel/booking confirmations).

A reservation PDF or photo has nothing to scan; the pass exists to remember the
booking. These tests pin the behaviour that makes such a pass useful: it is
generated at all, it survives the whole stay, and it carries the detail.
"""

import pytest

from app.core.models import StructuredMetadata
from app.core.pass_builder import _expiration, _relevant_date, _structure, _type_label


def _booking(**overrides) -> StructuredMetadata:
    base = dict(
        event_type="hotel_booking",
        title="Zander K Hotel",
        event_name="Zander K Hotel",
        venue_name="Zander K Hotel",
        date="2026-08-13",
        time="15:00",
        end_date="2026-08-15",
        end_time="11:00",
        confirmation_number="4831-77201-NO",
        venue_address="Zetlitzgaten 4, Bergen",
        phone="+47 55 30 90 80",
        price="NOK 3 480.00",
        duration="2 nights",
        amenities=["Breakfast included", "Free cancellation until 11 August 2026"],
    )
    base.update(overrides)
    return StructuredMetadata(**base)


def test_multi_day_booking_expires_after_checkout_not_checkin():
    """A stay must not vanish from Wallet partway through.

    Expiring off the start date made a 13→15 Aug booking expire on the 14th.
    """
    expiration = _expiration(_booking())

    assert expiration.startswith("2026-08-16"), (
        f"Expected expiry after the 15 Aug check-out, got {expiration}"
    )


def test_single_day_event_still_expires_the_day_after():
    expiration = _expiration(
        StructuredMetadata(title="Concert", event_type="concert", date="2026-08-13", time="20:00")
    )

    assert expiration.startswith("2026-08-14")


def test_no_date_falls_back_to_a_far_future_expiry():
    """A confirmation with no parseable date must still produce a usable pass."""
    expiration = _expiration(StructuredMetadata(title="Booking"))

    assert expiration > "2026-08-16"


def test_relevant_date_uses_checkin_datetime():
    """Drives the lock-screen suggestion when the guest arrives."""
    assert _relevant_date(_booking()) == "2026-08-13T15:00:00Z"


def test_relevant_date_absent_without_a_date():
    assert _relevant_date(StructuredMetadata(title="Booking")) is None


def test_booking_pass_shows_both_ends_of_the_stay():
    structure = _structure(_booking())
    labels = {f.label: f.value for f in structure.secondaryFields}

    assert labels.get("Check-in") == "2026-08-13"
    assert labels.get("Check-out") == "2026-08-15"


def test_single_date_event_is_labelled_date_not_checkin():
    structure = _structure(
        StructuredMetadata(title="Concert", event_type="concert", date="2026-08-13", time="20:00")
    )
    labels = {f.label for f in structure.secondaryFields}

    assert "Date" in labels
    assert "Check-in" not in labels
    assert "Check-out" not in labels


def test_reservation_detail_is_kept_on_the_pass():
    """The booking detail is the entire value of a barcode-less pass."""
    back = {f.label: f.value for f in _structure(_booking()).backFields}

    assert back["Phone"] == "+47 55 30 90 80"
    assert back["Duration"] == "2 nights"
    assert "Breakfast included" in back["Included"]
    assert "Zetlitzgaten 4" in back["Address"]


def test_venue_is_not_repeated_when_it_equals_the_title():
    auxiliary = {f.label for f in _structure(_booking()).auxiliaryFields}

    assert "Venue" not in auxiliary
    assert "Confirmation" in auxiliary


def test_venue_is_shown_when_it_differs_from_the_title():
    auxiliary = {
        f.label: f.value
        for f in _structure(_booking(title="Double Room", venue_name="Zander K Hotel")).auxiliaryFields
    }

    assert auxiliary.get("Venue") == "Zander K Hotel"


@pytest.mark.parametrize(
    ("event_type", "expected"),
    [
        ("hotel_booking", "HOTEL"),
        ("hotel", "HOTEL"),
        ("accommodation", "HOTEL"),
        ("train_ticket", "TRAIN"),
        ("car_rental", "RENTAL"),
        ("restaurant_reservation", "RESERVATION"),
        ("concert", "EVENT"),
        ("something_unknown", "TICKET"),
    ],
)
def test_type_label_matches_model_variants(event_type, expected):
    """The model answers 'hotel_booking', not 'hotel' — exact lookup said TICKET."""
    assert _type_label(event_type) == expected
