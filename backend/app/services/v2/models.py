"""Pydantic models for Apple Wallet pass.json schema and intermediate pipeline data."""

from __future__ import annotations

import re
from typing import Any, Dict, List, Literal, Optional, Union
from pydantic import BaseModel, Field, field_validator, model_validator


# ---------------------------------------------------------------------------
# Apple Wallet pass.json schema models
# ---------------------------------------------------------------------------

class PassField(BaseModel):
    """A single field displayed on the pass."""
    key: str
    label: str = ""
    value: str
    changeMessage: Optional[str] = None
    textAlignment: Optional[str] = None
    dateStyle: Optional[str] = None
    timeStyle: Optional[str] = None
    isRelative: Optional[bool] = None
    ignoresTimeZone: Optional[bool] = None
    currencyCode: Optional[str] = None
    numberStyle: Optional[str] = None
    attributedValue: Optional[str] = None


class PassStructure(BaseModel):
    """Fields for a pass style section (eventTicket, generic, etc.)."""
    headerFields: List[PassField] = []
    primaryFields: List[PassField] = []
    secondaryFields: List[PassField] = []
    auxiliaryFields: List[PassField] = []
    backFields: List[PassField] = []
    transitType: Optional[str] = None  # required for boardingPass only


class PKBarcode(BaseModel):
    """Apple Wallet barcode object."""
    format: Literal[
        "PKBarcodeFormatQR",
        "PKBarcodeFormatPDF417",
        "PKBarcodeFormatAztec",
        "PKBarcodeFormatCode128",
    ]
    message: str
    messageEncoding: str = "iso-8859-1"
    altText: Optional[str] = None


class PassLocation(BaseModel):
    """Location for pass relevance."""
    latitude: float
    longitude: float
    altitude: Optional[float] = None
    relevantText: Optional[str] = None


class PassJSON(BaseModel):
    """Complete Apple Wallet pass.json model."""
    formatVersion: int = 1
    passTypeIdentifier: str
    serialNumber: str
    teamIdentifier: str
    organizationName: str
    description: str
    logoText: Optional[str] = None
    foregroundColor: Optional[str] = None
    backgroundColor: Optional[str] = None
    labelColor: Optional[str] = None

    # Pass style — exactly one must be set
    eventTicket: Optional[PassStructure] = None
    generic: Optional[PassStructure] = None
    boardingPass: Optional[PassStructure] = None
    coupon: Optional[PassStructure] = None
    storeCard: Optional[PassStructure] = None

    # Barcodes — both legacy (barcode) and modern (barcodes) for compatibility
    barcode: Optional[PKBarcode] = None
    barcodes: Optional[List[PKBarcode]] = None

    # Optional metadata
    expirationDate: Optional[str] = None
    relevantDate: Optional[str] = None
    locations: Optional[List[PassLocation]] = None
    associatedStoreIdentifiers: Optional[List[int]] = None
    semantics: Optional[Dict[str, Any]] = None
    upcomingPassInformation: Optional[List[Dict[str, Any]]] = None
    webServiceURL: Optional[str] = None
    authenticationToken: Optional[str] = None

    @model_validator(mode="after")
    def check_pass_style(self) -> PassJSON:
        styles = [
            self.eventTicket,
            self.generic,
            self.boardingPass,
            self.coupon,
            self.storeCard,
        ]
        set_count = sum(1 for s in styles if s is not None)
        if set_count != 1:
            raise ValueError(f"Exactly one pass style must be set, found {set_count}")
        return self

    def model_dump_pass(self) -> Dict[str, Any]:
        """Serialize to pass.json-compatible dict (excludes None values)."""
        return self.model_dump(exclude_none=True)


# ---------------------------------------------------------------------------
# AI extraction models
# ---------------------------------------------------------------------------

class PDFExtraction(BaseModel):
    """Structured output from the AI extraction step."""
    document_type: Literal["event_ticket", "boarding_pass", "transit", "hotel", "generic"]
    title: str = Field(max_length=30, description="Concise title for the pass, max 30 chars")
    organization: Optional[str] = Field(default=None, description="Issuing organization name")
    event_name: Optional[str] = Field(default=None, description="Name of the event or experience")
    venue_name: Optional[str] = Field(default=None, description="Venue or location name only")
    venue_address: Optional[str] = Field(default=None, description="Street address of venue")
    date: Optional[str] = Field(default=None, description="ISO 8601 date (YYYY-MM-DD) if found")
    time: Optional[str] = Field(default=None, description="Time in HH:MM format if found")
    seat_info: Optional[str] = Field(default=None, description="Seat, row, or section info")
    gate_info: Optional[str] = Field(default=None, description="Gate, door, or platform info")
    confirmation_number: Optional[str] = Field(default=None, description="Booking or confirmation code")
    performer: Optional[str] = Field(default=None, description="Main performer, artist, or speaker")
    price: Optional[str] = Field(default=None, description="Ticket price if shown")
    confidence: int = Field(ge=0, le=100, description="Extraction confidence 0-100")

    @field_validator("title")
    @classmethod
    def sanitize_title(cls, v: str) -> str:
        v = v.strip()
        if not v:
            return "Digital Pass"
        # Reject UUID-like strings
        if re.fullmatch(r"[0-9a-fA-F\-]{32,}", v.replace("-", "")):
            return "Digital Pass"
        return v[:30]


# ---------------------------------------------------------------------------
# Barcode pipeline models
# ---------------------------------------------------------------------------

BARCODE_FORMAT_MAP: Dict[str, str] = {
    "QRCODE": "PKBarcodeFormatQR",
    "CODE128": "PKBarcodeFormatCode128",
    "PDF417": "PKBarcodeFormatPDF417",
    "AZTEC": "PKBarcodeFormatAztec",
    "CODE39": "PKBarcodeFormatCode128",
    "CODE93": "PKBarcodeFormatCode128",
    "EAN13": "PKBarcodeFormatCode128",
    "EAN8": "PKBarcodeFormatCode128",
    "UPC_A": "PKBarcodeFormatCode128",
    "UPC_E": "PKBarcodeFormatCode128",
    "CODABAR": "PKBarcodeFormatCode128",
    "ITF": "PKBarcodeFormatCode128",
}

UNSUPPORTED_FORMATS = {"DATAMATRIX"}


class ExtractedBarcode(BaseModel):
    """Normalized barcode from the extraction pipeline."""
    pk_format: str  # one of PKBarcodeFormat* values
    message: str
    message_encoding: str = "iso-8859-1"
    raw_bytes: Optional[bytes] = None
    source_type: str  # original detector type e.g. QRCODE, AZTEC
    confidence: int = 0
    warning: Optional[str] = None  # set when format was unsupported / coerced

    model_config = {"arbitrary_types_allowed": True}
