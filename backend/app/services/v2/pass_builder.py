"""Build a PassJSON model from extracted data.

Takes PDFExtraction + barcode info + colors and assembles a schema-valid
PassJSON that can then be validated and signed.
"""

from __future__ import annotations

import os
import uuid
from datetime import datetime, timedelta, timezone
from typing import List, Optional, Tuple

from app.services.v2.models import (
    ExtractedBarcode,
    PKBarcode,
    PassField,
    PassJSON,
    PassStructure,
    PDFExtraction,
)

# Pass styles that use eventTicket layout
_EVENT_TICKET_TYPES = {"event_ticket"}


def build_pass(
    extraction: PDFExtraction,
    barcodes: List[ExtractedBarcode],
    bg_color: str,
    fg_color: str,
    label_color: str,
    ticket_index: int = 0,
    total_tickets: int = 1,
    pass_type_id: str = "pass.com.andresboedo.add2wallet",
    team_id: str = "H9DPH4DQG7",
) -> PassJSON:
    """Construct a PassJSON from pipeline data."""

    title = extraction.title
    if total_tickets > 1:
        title = f"{title} (#{ticket_index + 1})"

    description = _build_description(extraction)
    if total_tickets > 1:
        description = f"{description} — Ticket {ticket_index + 1} of {total_tickets}"

    serial = str(uuid.uuid4())[:16]
    organization = extraction.organization or "Add2Wallet"

    # Choose pass style
    use_event_ticket = extraction.document_type in _EVENT_TICKET_TYPES
    structure = _build_structure(extraction, use_event_ticket)

    # Build barcode entries
    pk_barcode: Optional[PKBarcode] = None
    pk_barcodes: Optional[List[PKBarcode]] = None
    if barcodes:
        bc = barcodes[ticket_index] if ticket_index < len(barcodes) else barcodes[0]
        pk_barcode = PKBarcode(
            format=bc.pk_format,  # type: ignore[arg-type]
            message=bc.message,
            messageEncoding=bc.message_encoding,
        )
        pk_barcodes = [pk_barcode]
        print(f"🎫 Barcode: {bc.source_type} → {bc.pk_format}, {len(bc.message)} chars")

    # Expiration date
    expiry = _compute_expiry(extraction)

    # associatedStoreIdentifiers
    store_ids = _get_store_ids()

    pass_dict: dict = dict(
        formatVersion=1,
        passTypeIdentifier=pass_type_id,
        serialNumber=serial,
        teamIdentifier=team_id,
        organizationName=organization,
        description=description,
        logoText=title[:20],
        foregroundColor=fg_color,
        backgroundColor=bg_color,
        labelColor=label_color,
        expirationDate=expiry,
    )

    if store_ids:
        pass_dict["associatedStoreIdentifiers"] = store_ids

    if pk_barcode:
        pass_dict["barcode"] = pk_barcode
        pass_dict["barcodes"] = pk_barcodes

    if use_event_ticket:
        pass_dict["eventTicket"] = structure
    else:
        pass_dict["generic"] = structure

    return PassJSON(**pass_dict)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _build_structure(extraction: PDFExtraction, event_ticket: bool) -> PassStructure:
    header: List[PassField] = []
    primary: List[PassField] = []
    secondary: List[PassField] = []
    auxiliary: List[PassField] = []

    # Header — document / event type label
    type_label = _type_label(extraction.document_type)
    header.append(PassField(key="header", label=type_label, value=extraction.title[:25]))

    # Primary — main title
    primary.append(PassField(key="title", label="", value=extraction.title))

    # Secondary — date / time / seat (most important visible info)
    if extraction.date:
        secondary.append(PassField(key="date", label="Date", value=extraction.date))
    if extraction.time:
        secondary.append(PassField(key="time", label="Time", value=extraction.time))
    if extraction.seat_info:
        secondary.append(PassField(key="seat", label="Seat", value=extraction.seat_info))
    elif extraction.gate_info:
        secondary.append(PassField(key="gate", label="Gate", value=extraction.gate_info))

    # Auxiliary — venue / performer / confirmation / price
    if extraction.venue_name:
        auxiliary.append(PassField(key="venue", label="Venue", value=extraction.venue_name))
    if extraction.performer:
        auxiliary.append(PassField(key="performer", label="Artist", value=extraction.performer))
    if extraction.confirmation_number:
        auxiliary.append(
            PassField(key="confirmation", label="Confirmation", value=extraction.confirmation_number)
        )
    if extraction.price:
        auxiliary.append(PassField(key="price", label="Price", value=extraction.price))

    return PassStructure(
        headerFields=header,
        primaryFields=primary,
        secondaryFields=secondary,
        auxiliaryFields=auxiliary,
    )


def _type_label(document_type: str) -> str:
    mapping = {
        "event_ticket": "EVENT",
        "boarding_pass": "BOARDING",
        "transit": "TRANSIT",
        "hotel": "HOTEL",
        "generic": "DOCUMENT",
    }
    return mapping.get(document_type, "DOCUMENT")


def _build_description(extraction: PDFExtraction) -> str:
    parts = []
    if extraction.date:
        parts.append(extraction.date)
    if extraction.time:
        parts.append(extraction.time)
    if extraction.venue_name:
        parts.append(extraction.venue_name)
    if parts:
        return " • ".join(parts)[:80]
    return f"Digital pass"


def _compute_expiry(extraction: PDFExtraction) -> str:
    """Expire next day at 03:00 if a date is known, otherwise 90 days from now."""
    try:
        if extraction.date:
            from dateutil import parser as dp  # type: ignore

            combined = f"{extraction.date} {extraction.time}" if extraction.time else extraction.date
            dt = dp.parse(combined, fuzzy=True, dayfirst=False)
            expire = dt.replace(hour=3, minute=0, second=0, microsecond=0)
            if expire <= dt:
                expire = expire + timedelta(days=1)
            return expire.strftime("%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        pass
    return (datetime.utcnow() + timedelta(days=90)).strftime("%Y-%m-%dT%H:%M:%SZ")


def _get_store_ids() -> Optional[List[int]]:
    app_store_id = os.getenv("APP_STORE_ID")
    if app_store_id:
        try:
            return [int(app_store_id)]
        except ValueError:
            print(f"⚠️ Invalid APP_STORE_ID: {app_store_id}")
    return None
