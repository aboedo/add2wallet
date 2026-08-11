from __future__ import annotations

import json
import os
import tempfile
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from app.core.config import Settings
from app.core.errors import ProcessingError
from app.core.models import (
    AnalysisResult,
    Barcode,
    PassArtifact,
    PassSegment,
    StructuredMetadata,
    ValidatedUpload,
)
from app.services.v2.asset_generator import generate_assets
from app.services.v2.models import PKBarcode, PassField, PassJSON, PassStructure
from app.services.v2.pass_signer import get_signer
from app.core.pkpass_validation import validate_pkpass
from app.services.v2.pass_validator import validate_pass


class WalletPassBuilder:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def build(self, upload: ValidatedUpload, analysis: AnalysisResult) -> list[PassArtifact]:
        plan = _ticket_plan(analysis)
        artifacts: list[PassArtifact] = []
        for index, (segment, barcode) in enumerate(plan):
            metadata = _merge_segment(analysis.metadata, segment)
            pass_json = self._pass_json(metadata, barcode, index, len(plan), segment, analysis)
            valid, errors = validate_pass(pass_json)
            if not valid:
                raise ProcessingError(f"Pass validation failed: {'; '.join(errors)}")

            data = self._package(upload, analysis, pass_json, metadata)
            # The last gate before this leaves the building. `validate_pass`
            # above checked the JSON we were about to write; this checks the
            # archive we actually wrote, which is a different thing and the one
            # PassKit judges. Failing here is a bug in us, and a loud 500 beats
            # a file the device refuses with "the data format is invalid".
            if problems := validate_pkpass(data):
                raise ProcessingError(
                    "Built an invalid pkpass: " + "; ".join(problems)
                )
            artifacts.append(
                PassArtifact(
                    ticket_number=index + 1,
                    title=self._ticket_title(metadata, index, len(plan), segment),
                    description=pass_json.description,
                    barcode=barcode,
                    metadata=self._metadata_for_response(
                        metadata, index, len(plan), segment, analysis
                    ),
                    data=data,
                )
            )
        return artifacts

    def _ticket_count(self, analysis: AnalysisResult) -> int:
        if analysis.metadata.multiple_tickets and analysis.barcodes:
            return len(analysis.barcodes)
        # Several legs means several passes even when the model didn't flag the
        # document as multi-ticket; otherwise a five-leg itinerary collapsed
        # into a single pass carrying only the first leg.
        if analysis.segments:
            return max(len(analysis.barcodes), len(analysis.segments), 1)
        return 1

    def _pass_json(
        self,
        metadata: StructuredMetadata,
        barcode: Barcode | None,
        ticket_index: int,
        total_tickets: int,
        segment: PassSegment | None = None,
        analysis: AnalysisResult | None = None,
    ) -> PassJSON:
        signer = get_signer()
        pass_type, team_id = signer.get_identifiers()
        pass_type = pass_type or self.settings.pass_type_identifier
        team_id = team_id or self.settings.team_identifier

        title = self._ticket_title(metadata, ticket_index, total_tickets, segment)
        description = _description(metadata, segment)
        structure = _structure(metadata, segment, analysis)
        payload: dict[str, Any] = {
            "formatVersion": 1,
            "passTypeIdentifier": pass_type,
            "serialNumber": str(uuid.uuid4()),
            "teamIdentifier": team_id,
            "organizationName": metadata.organizer or metadata.venue_name or "Add2Wallet",
            "description": description,
            "logoText": title[:20],
            "foregroundColor": metadata.foreground_color,
            "backgroundColor": metadata.background_color,
            "labelColor": metadata.label_color,
            "expirationDate": _expiration(metadata),
            "relevantDate": _relevant_date(metadata),
            "eventTicket" if metadata.event_type in {"concert", "sports", "museum", "attraction", "theater", "festival", "event_ticket"} else "generic": structure,
        }
        if self.settings.app_store_id:
            payload["associatedStoreIdentifiers"] = [self.settings.app_store_id]
        if barcode:
            pk_barcode = PKBarcode(
                format=barcode.pk_format,  # type: ignore[arg-type]
                message=barcode.message,
                messageEncoding=barcode.message_encoding,
            )
            payload["barcode"] = pk_barcode
            payload["barcodes"] = [pk_barcode]
        if metadata.latitude is not None and metadata.longitude is not None:
            payload["locations"] = [
                {
                    "latitude": metadata.latitude,
                    "longitude": metadata.longitude,
                    "relevantText": metadata.venue_name,
                }
            ]
        return PassJSON(**payload)

    def _package(
        self,
        upload: ValidatedUpload,
        analysis: AnalysisResult,
        pass_json: PassJSON,
        metadata: StructuredMetadata | None = None,
    ) -> bytes:
        metadata = metadata or analysis.metadata
        with tempfile.TemporaryDirectory() as temp_dir:
            pass_path = os.path.join(temp_dir, "pass.json")
            with open(pass_path, "w") as f:
                json.dump(pass_json.model_dump_pass(), f, ensure_ascii=False, indent=2)
            pdf_for_thumbnail = upload.data if upload.kind.value == "pdf" else None
            generate_assets(
                temp_dir,
                pdf_for_thumbnail,
                metadata.event_type,
                metadata.title,
                metadata.background_color,
                metadata.foreground_color,
            )
            return get_signer().package_pass(temp_dir)

    def _ticket_title(
        self,
        metadata: StructuredMetadata,
        ticket_index: int,
        total_tickets: int,
        segment: PassSegment | None = None,
    ) -> str:
        # A leg names itself ("Train Bergen to Voss"); only fall back to a
        # numbered document title when there is nothing better.
        if segment and (segment.label or segment.route()):
            return (segment.label or segment.route() or "")[:30]
        title = (metadata.title or metadata.event_name or "Digital Pass")[:30]
        if total_tickets > 1:
            suffix = f" #{ticket_index + 1}"
            return f"{title[:30 - len(suffix)]}{suffix}"
        return title

    def _metadata_for_response(
        self,
        metadata: StructuredMetadata,
        ticket_index: int,
        total_tickets: int,
        segment: PassSegment | None = None,
        analysis: AnalysisResult | None = None,
    ) -> dict[str, Any]:
        data = metadata.model_dump(exclude_none=True)
        data["title"] = self._ticket_title(metadata, ticket_index, total_tickets, segment)
        if segment:
            data["segment"] = segment.model_dump(exclude_none=True)
            if segment.route():
                data["route"] = segment.route()
        if analysis and analysis.group_id:
            data["group_id"] = analysis.group_id
        if analysis and analysis.group_name:
            data["group_name"] = analysis.group_name
        if analysis and analysis.segments:
            data["group_size"] = len(analysis.barcodes) or len(analysis.segments)
        return data


def _sort_key(segment: PassSegment) -> tuple:
    """Chronological, falling back to the order the pages came in.

    Passes used to come out in whatever order the barcode scanner returned,
    which was by descending confidence — so a fjord cruise on the 18th could
    land between two trains on the 19th. The itinerary is the one thing that
    has an obviously correct order, and it is not "how sure were we that this
    was a QR code".
    """
    return (
        segment.depart_date or "9999-99-99",
        segment.depart_time or "99:99",
        segment.page if segment.page is not None else 9999,
    )


def _ticket_plan(analysis: AnalysisResult) -> list[tuple[PassSegment | None, Barcode | None]]:
    """One entry per pass to build: which leg it is, and which code it carries.

    How many passes a document is worth comes from what it *says* — "2 x Adult"
    on each of five legs is ten tickets — and not from how many barcode images
    were found. Those disagree constantly: Fjord Tours prints one QR per
    traveller on the trains, a single shared QR on the cruise, and an
    order-level QR on the bus, which counted as eight for a ten-ticket journey.
    """
    if not analysis.segments:
        # No legs: the old behaviour, one pass per code, is right for a plain
        # multi-ticket document where every code is its own admission.
        if analysis.metadata.multiple_tickets and analysis.barcodes:
            return [(None, barcode) for barcode in analysis.barcodes]
        return [(None, analysis.barcodes[0] if analysis.barcodes else None)]

    plan: list[tuple[PassSegment | None, Barcode | None]] = []
    for segment in sorted(analysis.segments, key=_sort_key):
        codes = [b for b in analysis.barcodes if b.page is not None and b.page == segment.page]
        # A leg is worth what it says it is worth. Where the document is silent,
        # fall back to the number of codes on that page, and never fewer than
        # one — a leg with no code at all is still a leg you travel.
        count = segment.traveler_count or len(codes) or 1
        for traveller in range(count):
            # Legs that print one code per traveller hand each pass its own;
            # legs that print one shared code give everyone the same one, which
            # is exactly what the paper ticket does.
            code = codes[traveller] if traveller < len(codes) else (codes[0] if codes else None)
            plan.append((segment, code))
    return plan


def _segment_for(
    analysis: AnalysisResult, barcode: Barcode | None, ticket_index: int
) -> PassSegment | None:
    """Match a pass to its leg — by the page its barcode came from."""
    if not analysis.segments:
        return None
    if barcode is not None and barcode.page is not None:
        for segment in analysis.segments:
            if segment.page == barcode.page:
                return segment
    # No page information (image upload, or a code the scanner couldn't place):
    # fall back to position, which is right for a one-code-per-leg document.
    if ticket_index < len(analysis.segments):
        return analysis.segments[ticket_index]
    return None


def _merge_segment(metadata: StructuredMetadata, segment: PassSegment | None) -> StructuredMetadata:
    """Overlay a leg's own detail on the document-level metadata."""
    if segment is None:
        return metadata

    merged = metadata.model_copy(deep=True)
    if segment.label:
        merged.title = segment.label[:60]
        merged.event_name = segment.label
    if segment.depart_date:
        merged.date = segment.depart_date
    if segment.depart_time:
        merged.time = segment.depart_time
    # A leg ends the same day it starts; end_* would otherwise still describe
    # the whole trip and push the expiry far past this leg.
    merged.end_date = segment.arrive_date
    merged.end_time = segment.arrive_time
    if segment.seat_info:
        merged.seat_info = segment.seat_info
    if segment.confirmation_number:
        merged.confirmation_number = segment.confirmation_number
    if segment.carrier:
        merged.organizer = segment.carrier
    if segment.origin:
        merged.venue_name = segment.origin
    return merged


def _structure(
    metadata: StructuredMetadata,
    segment: PassSegment | None = None,
    analysis: AnalysisResult | None = None,
) -> PassStructure:
    secondary: list[PassField] = []
    auxiliary: list[PassField] = []
    back: list[PassField] = []

    # A journey leg leads with its route and departure/arrival times; that is
    # what tells two passes of the same booking apart at a glance.
    if segment and segment.route():
        primary = [PassField(key="route", label="", value=segment.route() or "")]
        if segment.depart_time:
            secondary.append(
                PassField(
                    key="depart",
                    label=f"Depart{f' · {segment.origin}' if segment.origin else ''}"[:16],
                    value=f"{segment.depart_time}{f'  {segment.depart_date}' if segment.depart_date else ''}",
                )
            )
        if segment.arrive_time:
            secondary.append(
                PassField(
                    key="arrive",
                    label=f"Arrive{f' · {segment.destination}' if segment.destination else ''}"[:16],
                    value=f"{segment.arrive_time}{f'  {segment.arrive_date}' if segment.arrive_date else ''}",
                )
            )
        if segment.seat_info:
            secondary.append(PassField(key="seat", label="Seat", value=segment.seat_info))
        if segment.carrier:
            auxiliary.append(PassField(key="carrier", label="Operator", value=segment.carrier))
        if segment.vehicle_info:
            auxiliary.append(PassField(key="vehicle", label="Service", value=segment.vehicle_info))
        if segment.travel_class:
            auxiliary.append(PassField(key="class", label="Class", value=segment.travel_class))
        if segment.confirmation_number:
            auxiliary.append(
                PassField(key="confirmation", label="Reference", value=segment.confirmation_number)
            )
        if segment.traveler:
            back.append(PassField(key="traveler", label="Traveller", value=segment.traveler))
        if segment.notes:
            back.append(PassField(key="notes", label="Good to know", value=segment.notes))
        if analysis and analysis.group_name:
            back.append(PassField(key="trip", label="Trip", value=analysis.group_name))
        if analysis and analysis.group_id:
            back.append(PassField(key="order", label="Order", value=analysis.group_id))
        if metadata.venue_address:
            back.append(PassField(key="address", label="Address", value=metadata.venue_address))
        if metadata.description:
            back.append(PassField(key="description", label="Details", value=metadata.description))
        return PassStructure(
            headerFields=[
                PassField(key="kind", label="PASS", value=_type_label(metadata.event_type))
            ],
            primaryFields=primary,
            secondaryFields=secondary,
            auxiliaryFields=auxiliary,
            backFields=back,
        )

    primary = [PassField(key="title", label="", value=metadata.title or metadata.event_name or "Digital Pass")]

    # A stay/rental shows both ends of the range; a point-in-time event just
    # shows when it starts.
    is_range = bool(metadata.end_date and metadata.end_date != metadata.date)
    if metadata.date:
        secondary.append(
            PassField(key="date", label="Check-in" if is_range else "Date", value=metadata.date)
        )
    if is_range:
        secondary.append(PassField(key="end_date", label="Check-out", value=metadata.end_date))
    if metadata.time:
        secondary.append(PassField(key="time", label="From" if is_range else "Time", value=metadata.time))
    if metadata.seat_info:
        secondary.append(PassField(key="seat", label="Seat", value=metadata.seat_info))
    if metadata.gate_info:
        secondary.append(PassField(key="gate", label="Gate", value=metadata.gate_info))
    # Skip a venue that just repeats the title — common on booking documents.
    if metadata.venue_name and metadata.venue_name != (metadata.title or metadata.event_name):
        auxiliary.append(PassField(key="venue", label="Venue", value=metadata.venue_name))
    if metadata.performer_artist:
        auxiliary.append(PassField(key="performer", label="Performer", value=metadata.performer_artist))
    if metadata.confirmation_number:
        auxiliary.append(PassField(key="confirmation", label="Confirmation", value=metadata.confirmation_number))
    if metadata.price:
        auxiliary.append(PassField(key="price", label="Price", value=metadata.price))
    if metadata.venue_address:
        back.append(PassField(key="address", label="Address", value=metadata.venue_address))
    # Detail worth keeping on a barcode-less reservation: the whole point of
    # that pass is remembering the booking, not scanning it.
    if metadata.phone:
        back.append(PassField(key="phone", label="Phone", value=metadata.phone))
    if metadata.website:
        back.append(PassField(key="website", label="Website", value=metadata.website))
    if metadata.duration:
        back.append(PassField(key="duration", label="Duration", value=metadata.duration))
    if metadata.amenities:
        back.append(
            PassField(key="amenities", label="Included", value=", ".join(metadata.amenities))
        )
    if metadata.accessibility:
        back.append(PassField(key="accessibility", label="Accessibility", value=metadata.accessibility))
    if metadata.description:
        back.append(PassField(key="description", label="Description", value=metadata.description))

    return PassStructure(
        headerFields=[PassField(key="kind", label="PASS", value=_type_label(metadata.event_type))],
        primaryFields=primary,
        secondaryFields=secondary,
        auxiliaryFields=auxiliary,
        backFields=back,
    )


def _description(metadata: StructuredMetadata, segment: PassSegment | None = None) -> str:
    if segment and segment.route():
        parts = [segment.route(), segment.depart_date, segment.depart_time]
    else:
        parts = [metadata.event_name, metadata.date, metadata.venue_name]
    parts = [part for part in parts if part]
    return " - ".join(parts)[:80] if parts else "Digital pass"


def _expiration(metadata: StructuredMetadata) -> str:
    # Expire off the END of the booking when there is one. Using the start date
    # made multi-day reservations (hotel stays, rentals) vanish from Wallet
    # partway through the stay.
    last_day = metadata.end_date or metadata.date
    if last_day:
        parsed = _parse_datetime(last_day, metadata.end_time if metadata.end_date else metadata.time)
        if parsed:
            return (parsed + timedelta(days=1)).strftime("%Y-%m-%dT03:00:00Z")
    return (datetime.now(timezone.utc) + timedelta(days=90)).strftime("%Y-%m-%dT%H:%M:%SZ")


def _relevant_date(metadata: StructuredMetadata) -> str | None:
    """When Wallet should surface the pass — check-in time / event start."""
    if not metadata.date:
        return None
    parsed = _parse_datetime(metadata.date, metadata.time)
    return parsed.strftime("%Y-%m-%dT%H:%M:%SZ") if parsed else None


def _parse_datetime(date_value: str, time_value: str | None) -> datetime | None:
    try:
        from dateutil import parser

        return parser.parse(f"{date_value} {time_value or ''}".strip(), fuzzy=True)
    except Exception:
        return None


def _type_label(event_type: str) -> str:
    # Matched on a substring: the model returns variants like "hotel_booking",
    # "train_ticket" or "car_rental", which an exact lookup labelled "TICKET".
    normalized = (event_type or "").lower()
    for needle, label in (
        ("hotel", "HOTEL"),
        ("lodging", "HOTEL"),
        ("accommodation", "HOTEL"),
        ("flight", "FLIGHT"),
        ("ferry", "FERRY"),
        ("bus", "BUS"),
        ("train", "TRAIN"),
        ("rail", "TRAIN"),
        ("rental", "RENTAL"),
        ("restaurant", "RESERVATION"),
        ("dining", "RESERVATION"),
        ("booking", "BOOKING"),
        ("reservation", "BOOKING"),
        ("concert", "EVENT"),
        ("sports", "SPORTS"),
        ("museum", "MUSEUM"),
        ("attraction", "TICKET"),
    ):
        if needle in normalized:
            return label
    return "TICKET"

