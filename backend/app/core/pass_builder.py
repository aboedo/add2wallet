from __future__ import annotations

import json
import os
import tempfile
import uuid
from datetime import datetime, timedelta
from typing import Any

from app.core.config import Settings
from app.core.errors import ProcessingError
from app.core.models import AnalysisResult, Barcode, PassArtifact, StructuredMetadata, ValidatedUpload
from app.services.v2.asset_generator import generate_assets
from app.services.v2.models import PKBarcode, PassField, PassJSON, PassStructure
from app.services.v2.pass_signer import get_signer
from app.services.v2.pass_validator import validate_pass


class WalletPassBuilder:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def build(self, upload: ValidatedUpload, analysis: AnalysisResult) -> list[PassArtifact]:
        ticket_count = self._ticket_count(analysis)
        artifacts: list[PassArtifact] = []
        for index in range(ticket_count):
            barcode = analysis.barcodes[index] if index < len(analysis.barcodes) else (analysis.barcodes[0] if analysis.barcodes else None)
            pass_json = self._pass_json(analysis.metadata, barcode, index, ticket_count)
            valid, errors = validate_pass(pass_json)
            if not valid:
                raise ProcessingError(f"Pass validation failed: {'; '.join(errors)}")

            data = self._package(upload, analysis, pass_json)
            artifacts.append(
                PassArtifact(
                    ticket_number=index + 1,
                    title=self._ticket_title(analysis.metadata, index, ticket_count),
                    description=pass_json.description,
                    barcode=barcode,
                    metadata=self._metadata_for_response(analysis.metadata, index, ticket_count),
                    data=data,
                )
            )
        return artifacts

    def _ticket_count(self, analysis: AnalysisResult) -> int:
        if analysis.metadata.multiple_tickets and analysis.barcodes:
            return len(analysis.barcodes)
        return 1

    def _pass_json(
        self,
        metadata: StructuredMetadata,
        barcode: Barcode | None,
        ticket_index: int,
        total_tickets: int,
    ) -> PassJSON:
        signer = get_signer()
        pass_type, team_id = signer.get_identifiers()
        pass_type = pass_type or self.settings.pass_type_identifier
        team_id = team_id or self.settings.team_identifier

        title = self._ticket_title(metadata, ticket_index, total_tickets)
        description = _description(metadata)
        structure = _structure(metadata)
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

    def _package(self, upload: ValidatedUpload, analysis: AnalysisResult, pass_json: PassJSON) -> bytes:
        with tempfile.TemporaryDirectory() as temp_dir:
            pass_path = os.path.join(temp_dir, "pass.json")
            with open(pass_path, "w") as f:
                json.dump(pass_json.model_dump_pass(), f, ensure_ascii=False, indent=2)
            pdf_for_thumbnail = upload.data if upload.kind.value == "pdf" else None
            generate_assets(
                temp_dir,
                pdf_for_thumbnail,
                analysis.metadata.event_type,
                analysis.metadata.title,
                analysis.metadata.background_color,
                analysis.metadata.foreground_color,
            )
            return get_signer().package_pass(temp_dir)

    def _ticket_title(self, metadata: StructuredMetadata, ticket_index: int, total_tickets: int) -> str:
        title = (metadata.title or metadata.event_name or "Digital Pass")[:30]
        if total_tickets > 1:
            suffix = f" #{ticket_index + 1}"
            return f"{title[:30 - len(suffix)]}{suffix}"
        return title

    def _metadata_for_response(self, metadata: StructuredMetadata, ticket_index: int, total_tickets: int) -> dict[str, Any]:
        data = metadata.model_dump(exclude_none=True)
        data["title"] = self._ticket_title(metadata, ticket_index, total_tickets)
        return data


def _structure(metadata: StructuredMetadata) -> PassStructure:
    primary = [PassField(key="title", label="", value=metadata.title or metadata.event_name or "Digital Pass")]
    secondary: list[PassField] = []
    auxiliary: list[PassField] = []
    back: list[PassField] = []

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


def _description(metadata: StructuredMetadata) -> str:
    parts = [part for part in [metadata.event_name, metadata.date, metadata.venue_name] if part]
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
    return (datetime.utcnow() + timedelta(days=90)).strftime("%Y-%m-%dT%H:%M:%SZ")


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

