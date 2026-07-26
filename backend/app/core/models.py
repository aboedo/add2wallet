from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field


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


class AnalysisResult(BaseModel):
    text: str = ""
    page_count: int = 1
    metadata: StructuredMetadata
    barcodes: list[Barcode] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


class ExtractedDocument(BaseModel):
    text: str = ""
    page_count: int = 1
    vision_images: list[tuple[bytes, str]] = Field(default_factory=list)
    barcodes: list[Barcode] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


class ClassifiedDocument(BaseModel):
    metadata: StructuredMetadata
    barcodes: list[Barcode] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


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
