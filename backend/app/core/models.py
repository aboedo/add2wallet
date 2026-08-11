from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any
from zoneinfo import available_timezones

from pydantic import BaseModel, Field, field_validator


class DocumentKind(str, Enum):
    pdf = "pdf"
    jpeg = "jpeg"
    png = "png"
    heic = "heic"


class ValidatedUpload(BaseModel):
    filename: str
    content_type: str | None
    kind: DocumentKind
    data: bytes
    extension: str


class Barcode(BaseModel):
    type: str
    pk_format: str
    message: str
    message_encoding: str = "iso-8859-1"
    confidence: int = 0
    # 0-based page the code was found on. A multi-leg itinerary puts one leg
    # per page, so this is what lets each pass carry its own segment's detail
    # instead of the whole document's.
    page: int | None = None


class StructuredMetadata(BaseModel):
    event_type: str = "other"
    event_name: str | None = None
    title: str = "Digital Pass"
    description: str | None = None
    date: str | None = None
    time: str | None = None
    # End of a multi-day stay/booking (hotel check-out, rental return). Drives
    # the pass expiration so a reservation doesn't disappear mid-stay.
    end_date: str | None = None
    end_time: str | None = None
    duration: str | None = None
    venue_name: str | None = None
    venue_address: str | None = None
    city: str | None = None
    state_country: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    organizer: str | None = None
    performer_artist: str | None = None
    seat_info: str | None = None
    barcode_data: str | None = None
    price: str | None = None
    confirmation_number: str | None = None
    gate_info: str | None = None
    event_description: str | None = None
    venue_type: str | None = None
    capacity: str | None = None
    website: str | None = None
    phone: str | None = None
    nearby_landmarks: list[str] | None = None
    public_transport: str | None = None
    parking_info: str | None = None
    age_restriction: str | None = None
    dress_code: str | None = None
    weather_considerations: str | None = None
    amenities: list[str] | None = None
    accessibility: str | None = None
    ai_processed: bool = False
    confidence_score: int | None = None
    processing_timestamp: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    model_used: str | None = None
    enrichment_completed: bool = False
    # Brand colour the model infers from what the document is about (a club's
    # kit, an airline's livery). None means it had nothing to go on, which is
    # what lets the pixel extractor take over instead of always winning.
    brand_color: str | None = None
    background_color: str = "rgb(22, 82, 96)"
    foreground_color: str = "rgb(255, 255, 255)"
    label_color: str = "rgb(210, 235, 238)"
    multiple_events: bool = False
    upcoming_events: list[dict[str, Any]] | None = None
    venue_place_id: str | None = None
    performer_names: list[str] | None = None
    exhibit_name: str | None = None
    has_assigned_seating: bool = False
    event_urls: dict[str, Any] | None = None
    multiple_tickets: bool = False

    model_config = {"protected_namespaces": ()}


class PassSegment(BaseModel):
    """One leg of a multi-part document — a train ride, a night, a session.

    A "Norway in a Nutshell" itinerary is five legs across five pages, each
    with its own route, times, seats and provider reference. Extracting only
    document-level metadata produced N near-identical passes and threw all of
    that away.
    """

    page: int | None = None
    label: str | None = None
    origin: str | None = None
    destination: str | None = None
    depart_date: str | None = None
    depart_time: str | None = None
    arrive_date: str | None = None
    arrive_time: str | None = None
    # IANA zone names ("Europe/Madrid"), never fixed offsets.
    #
    # An offset is only true for a date: "+02:00" is Madrid in August and wrong
    # in January, so storing what the document printed would quietly break
    # every itinerary twice a year. The zone plus the departure date gives the
    # offset back whenever it is needed; the reverse does not hold.
    #
    # Times themselves stay local and unconverted. A boarding pass says 13:35
    # because that is what the airport clock will say, and a traveller checking
    # this screen is standing under that clock.
    depart_timezone: str | None = None
    arrive_timezone: str | None = None
    carrier: str | None = None
    vehicle_info: str | None = None
    seat_info: str | None = None
    travel_class: str | None = None
    confirmation_number: str | None = None
    traveler: str | None = None
    notes: str | None = None

    @field_validator("depart_timezone", "arrive_timezone", mode="after")
    @classmethod
    def _only_real_zones(cls, value: str | None) -> str | None:
        """Drop anything that is not a zone the system actually knows.

        The prompt asks for IANA names and forbids offsets, but the model is
        not a parser and will occasionally answer "GMT-3", "CET", or a plausible
        city that is not a zone. Every one of those would be read later as
        authoritative and shift a departure time by hours. Verifying is one set
        lookup, so there is no reason to take the model's word for it.
        """
        if not value:
            return None
        return value if value in available_timezones() else None

    def route(self) -> str | None:
        if self.origin and self.destination:
            return f"{self.origin} → {self.destination}"
        return self.origin or self.destination


class AnalysisResult(BaseModel):
    text: str = ""
    page_count: int = 1
    metadata: StructuredMetadata
    barcodes: list[Barcode] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    # Per-leg detail, when the document describes several. Empty for a plain
    # single-event ticket.
    segments: list[PassSegment] = Field(default_factory=list)
    # Shared booking/order reference, so related passes can be grouped.
    group_id: str | None = None
    group_name: str | None = None


class ExtractedDocument(BaseModel):
    text: str = ""
    page_count: int = 1
    # Text per page, index-aligned with Barcode.page.
    pages: list[str] = Field(default_factory=list)
    vision_images: list[tuple[bytes, str]] = Field(default_factory=list)
    barcodes: list[Barcode] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


class ClassifiedDocument(BaseModel):
    metadata: StructuredMetadata
    barcodes: list[Barcode] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    segments: list[PassSegment] = Field(default_factory=list)
    group_id: str | None = None
    group_name: str | None = None


class PassArtifact(BaseModel):
    ticket_number: int
    title: str
    description: str
    barcode: Barcode | None = None
    metadata: dict[str, Any]
    data: bytes


class StoredJob(BaseModel):
    job_id: str
    user_id: str
    status: str
    progress: int
    filename: str
    created_at: float
    file_path: Path
    pass_paths: list[Path] = Field(default_factory=list)
    ticket_info: list[dict[str, Any]] = Field(default_factory=list)
    detected_barcodes: list[dict[str, Any]] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    ai_metadata: dict[str, Any] | None = None
    ticket_count: int = 0
    barcode_count: int = 0
    remaining_passes: int | None = None
    error: str | None = None
