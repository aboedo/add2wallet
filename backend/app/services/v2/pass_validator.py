"""Validate a PassJSON model against Apple Wallet spec before signing."""

from __future__ import annotations

import re
from typing import List, Tuple, Optional

from app.services.v2.models import PassJSON, PassField, PassStructure

_RGB_PATTERN = re.compile(r"^rgb\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)$")
_ISO8601_PATTERN = re.compile(
    r"^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2})?(\.\d+)?(Z|[+-]\d{2}:\d{2})?)?$"
)
_VALID_BARCODE_FORMATS = {
    "PKBarcodeFormatQR",
    "PKBarcodeFormatPDF417",
    "PKBarcodeFormatAztec",
    "PKBarcodeFormatCode128",
}


def validate_pass(pass_json: PassJSON) -> Tuple[bool, List[str]]:
    """Validate a PassJSON instance against Apple Wallet requirements.

    Returns (is_valid, list_of_error_messages).
    """
    errors: List[str] = []

    # --- Required top-level fields ---
    _require_nonempty(pass_json.formatVersion is not None, "formatVersion is required", errors)
    _require_nonempty(bool(pass_json.passTypeIdentifier), "passTypeIdentifier is required", errors)
    _require_nonempty(bool(pass_json.serialNumber), "serialNumber is required", errors)
    _require_nonempty(bool(pass_json.teamIdentifier), "teamIdentifier is required", errors)
    _require_nonempty(bool(pass_json.organizationName), "organizationName is required", errors)
    _require_nonempty(bool(pass_json.description), "description is required", errors)

    if pass_json.formatVersion != 1:
        errors.append(f"formatVersion must be 1, got {pass_json.formatVersion}")

    # --- Exactly one pass style ---
    style_fields = {
        "eventTicket": pass_json.eventTicket,
        "generic": pass_json.generic,
        "boardingPass": pass_json.boardingPass,
        "coupon": pass_json.coupon,
        "storeCard": pass_json.storeCard,
    }
    set_styles = [k for k, v in style_fields.items() if v is not None]
    if len(set_styles) != 1:
        errors.append(
            f"Exactly one pass style must be set; found {len(set_styles)}: {set_styles}"
        )

    # --- boardingPass requires transitType ---
    if pass_json.boardingPass is not None:
        valid_transit = {"PKTransitTypeAir", "PKTransitTypeBoat", "PKTransitTypeBus", "PKTransitTypeGeneric", "PKTransitTypeTrain"}
        if not pass_json.boardingPass.transitType:
            errors.append("boardingPass requires transitType")
        elif pass_json.boardingPass.transitType not in valid_transit:
            errors.append(f"boardingPass.transitType '{pass_json.boardingPass.transitType}' is not valid")

    # --- Color values ---
    for color_field in ("foregroundColor", "backgroundColor", "labelColor"):
        value: Optional[str] = getattr(pass_json, color_field)
        if value is not None and not _valid_rgb(value):
            errors.append(f"{color_field} '{value}' is not a valid rgb(r,g,b) string")

    # --- Barcode formats ---
    if pass_json.barcode is not None:
        if pass_json.barcode.format not in _VALID_BARCODE_FORMATS:
            errors.append(f"barcode.format '{pass_json.barcode.format}' is not a valid PKBarcodeFormat")
        if not pass_json.barcode.message:
            errors.append("barcode.message must not be empty")

    if pass_json.barcodes:
        for i, bc in enumerate(pass_json.barcodes):
            if bc.format not in _VALID_BARCODE_FORMATS:
                errors.append(f"barcodes[{i}].format '{bc.format}' is not valid")
            if not bc.message:
                errors.append(f"barcodes[{i}].message must not be empty")

    # --- Field key uniqueness per array ---
    for style_name, structure in style_fields.items():
        if structure is None:
            continue
        _check_unique_keys(style_name, "headerFields", structure.headerFields, errors)
        _check_unique_keys(style_name, "primaryFields", structure.primaryFields, errors)
        _check_unique_keys(style_name, "secondaryFields", structure.secondaryFields, errors)
        _check_unique_keys(style_name, "auxiliaryFields", structure.auxiliaryFields, errors)
        _check_unique_keys(style_name, "backFields", structure.backFields, errors)

    # --- ISO 8601 dates ---
    for date_field in ("expirationDate", "relevantDate"):
        value = getattr(pass_json, date_field)
        if value is not None and not _valid_iso8601(value):
            errors.append(f"{date_field} '{value}' is not a valid ISO 8601 date string")

    return len(errors) == 0, errors


def _require_nonempty(condition: bool, message: str, errors: List[str]) -> None:
    if not condition:
        errors.append(message)


def _valid_rgb(value: str) -> bool:
    match = _RGB_PATTERN.match(value)
    if not match:
        return False
    for i in range(1, 4):
        if int(match.group(i)) > 255:
            return False
    return True


def _valid_iso8601(value: str) -> bool:
    return bool(_ISO8601_PATTERN.match(value))


def _check_unique_keys(
    style: str,
    field_name: str,
    fields: List[PassField],
    errors: List[str],
) -> None:
    seen: set = set()
    for field in fields:
        if field.key in seen:
            errors.append(
                f"{style}.{field_name} has duplicate key '{field.key}'"
            )
        seen.add(field.key)
