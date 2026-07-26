from __future__ import annotations

import asyncio
import base64
import json
import logging
import re
from datetime import datetime, timezone
from typing import Any, Union, get_args, get_origin

from openai import APIStatusError, AuthenticationError, OpenAI, RateLimitError
from pydantic import ValidationError

from app.core.config import Settings
from app.core.errors import UpstreamServiceError
from app.core.models import DocumentKind, StructuredMetadata


logger = logging.getLogger(__name__)


class MetadataExtractor:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.client = (
            OpenAI(api_key=settings.openai_api_key, timeout=30.0)
            if settings.openai_api_key
            else None
        )

    async def extract_from_text(
        self,
        text: str,
        filename: str,
        barcode_messages: list[str],
    ) -> StructuredMetadata:
        if not self.client:
            return fallback_metadata(text, filename, barcode_messages, self.settings.openai_model)

        prompt = _metadata_prompt(filename, text[:6000], barcode_messages)
        try:
            response = await asyncio.to_thread(
                self.client.chat.completions.create,
                model=self.settings.openai_model,
                messages=[
                    {
                        "role": "system",
                        "content": "Extract Apple Wallet pass metadata from tickets, receipts, bookings, and travel documents. Return JSON only.",
                    },
                    {"role": "user", "content": prompt},
                ],
                temperature=0.1,
                max_tokens=1200,
            )
            return _metadata_from_json(response.choices[0].message.content or "", self.settings.openai_model)
        except (AuthenticationError, RateLimitError) as exc:
            raise UpstreamServiceError("OpenAI metadata extraction is unavailable") from exc
        except APIStatusError as exc:
            if exc.status_code in {401, 402, 429}:
                raise UpstreamServiceError("OpenAI metadata extraction is unavailable") from exc
            logger.warning("OpenAI text extraction failed; using fallback", exc_info=True)
            return fallback_metadata(text, filename, barcode_messages, self.settings.openai_model)
        except Exception:
            logger.warning("OpenAI text extraction failed; using fallback", exc_info=True)
            return fallback_metadata(text, filename, barcode_messages, self.settings.openai_model)

    async def extract_from_vision(
        self,
        images: list[tuple[bytes, str]],
        filename: str,
        barcode_messages: list[str],
        fallback_text: str = "",
    ) -> StructuredMetadata:
        if not self.client or not images:
            return fallback_metadata(fallback_text, filename, barcode_messages, self.settings.openai_model)

        content: list[dict[str, Any]] = [
            {
                "type": "text",
                "text": _metadata_prompt(filename, fallback_text[:2000], barcode_messages)
                + "\nRead the attached image(s) visually, including ticket text, QR labels, seats, venue, and dates.",
            }
        ]
        for data, media_type in images[:3]:
            encoded = base64.b64encode(data).decode("ascii")
            content.append(
                {
                    "type": "image_url",
                    "image_url": {"url": f"data:{media_type};base64,{encoded}"},
                }
            )

        try:
            response = await asyncio.to_thread(
                self.client.chat.completions.create,
                model=self.settings.openai_model,
                messages=[
                    {
                        "role": "system",
                        "content": "Extract Apple Wallet pass metadata from ticket images. Return JSON only.",
                    },
                    {"role": "user", "content": content},
                ],
                temperature=0.1,
                max_tokens=1200,
            )
            return _metadata_from_json(response.choices[0].message.content or "", self.settings.openai_model)
        except (AuthenticationError, RateLimitError) as exc:
            raise UpstreamServiceError("OpenAI vision extraction is unavailable") from exc
        except APIStatusError as exc:
            if exc.status_code in {401, 402, 429}:
                raise UpstreamServiceError("OpenAI vision extraction is unavailable") from exc
            logger.warning("OpenAI vision extraction failed; using fallback", exc_info=True)
            return fallback_metadata(fallback_text, filename, barcode_messages, self.settings.openai_model)
        except Exception:
            logger.warning("OpenAI vision extraction failed; using fallback", exc_info=True)
            return fallback_metadata(fallback_text, filename, barcode_messages, self.settings.openai_model)


def fallback_metadata(
    text: str,
    filename: str,
    barcode_messages: list[str],
    model: str | None = None,
) -> StructuredMetadata:
    clean_name = re.sub(r"\.[A-Za-z0-9]+$", "", filename or "Digital Pass")
    clean_name = re.sub(r"[_\-]+", " ", clean_name).strip()
    title = _sensible_title(text, clean_name)
    date_match = re.search(r"\b(\d{4}-\d{2}-\d{2}|\d{1,2}[./-]\d{1,2}[./-]\d{2,4})\b", text)
    time_match = re.search(r"\b(\d{1,2}:\d{2}\s?(?:AM|PM)?)\b", text, re.IGNORECASE)
    return StructuredMetadata(
        event_name=title,
        title=title,
        description=f"Digital pass from {filename or 'uploaded document'}",
        date=date_match.group(1) if date_match else None,
        time=time_match.group(1) if time_match else None,
        barcode_data=barcode_messages[0] if barcode_messages else None,
        ai_processed=False,
        confidence_score=30,
        model_used=model,
        enrichment_completed=False,
    )


def _metadata_from_json(raw: str, model: str) -> StructuredMetadata:
    text = raw.strip()
    if "```json" in text:
        start = text.find("```json") + len("```json")
        end = text.find("```", start)
        text = text[start:end].strip()
    elif "{" in text:
        text = text[text.find("{") : text.rfind("}") + 1]

    data = json.loads(text)
    if data.get("performer") and not data.get("performer_artist"):
        data["performer_artist"] = data["performer"]
    if data.get("confidence") and not data.get("confidence_score"):
        data["confidence_score"] = data["confidence"]
    data["ai_processed"] = True
    data["enrichment_completed"] = True
    data["processing_timestamp"] = datetime.now(timezone.utc).isoformat()
    data["model_used"] = model

    known = _coerce_to_schema({k: v for k, v in data.items() if k in StructuredMetadata.model_fields})
    try:
        return StructuredMetadata(**known)
    except ValidationError as exc:
        # Never discard a whole extraction over one malformed field — that
        # silently downgraded every document to regex fallback.
        unusable = {str(error["loc"][0]) for error in exc.errors() if error.get("loc")}
        logger.warning("Dropping unusable AI metadata fields: %s", sorted(unusable))
        return StructuredMetadata(**{k: v for k, v in known.items() if k not in unusable})


def _coerce_to_schema(data: dict[str, Any]) -> dict[str, Any]:
    """Reshape a model's JSON so StructuredMetadata will accept it.

    The LLM regularly answers with ``null`` for fields that are typed as plain
    ``bool``/``str`` with a default, and with a *list* where a single string is
    expected (``barcode_data`` and ``confirmation_number`` on multi-ticket
    documents). Pydantic rejected those payloads, the broad ``except`` above
    swallowed the error, and the pass was built from regex fallback instead —
    so the extraction was paid for and thrown away on essentially every file.
    """
    coerced: dict[str, Any] = {}
    for key, value in data.items():
        annotation = StructuredMetadata.model_fields[key].annotation
        allows_none = _allows_none(annotation)

        if value is None:
            # Let the field default apply rather than failing validation.
            if allows_none:
                coerced[key] = None
            continue

        base = _non_none_type(annotation)
        origin = get_origin(base)

        if origin in (list, tuple, set):
            coerced[key] = list(value) if isinstance(value, (list, tuple, set)) else [value]
            continue

        if isinstance(value, (list, tuple, set)):
            # Collapse a collection into the scalar the schema asks for. Take
            # the first entry rather than joining: these are identifiers
            # (barcode payload, confirmation number), not prose.
            scalars = [str(item) for item in value if item not in (None, "")]
            if not scalars:
                continue
            coerced[key] = scalars[0]
            continue

        if base is bool and not isinstance(value, bool):
            if isinstance(value, str):
                lowered = value.strip().lower()
                if lowered in ("true", "yes", "1"):
                    coerced[key] = True
                elif lowered in ("false", "no", "0", ""):
                    coerced[key] = False
                continue
            coerced[key] = bool(value)
            continue

        if base is str and not isinstance(value, str):
            coerced[key] = str(value)
            continue

        coerced[key] = value
    return coerced


def _non_none_type(annotation: Any) -> Any:
    args = [arg for arg in get_args(annotation) if arg is not type(None)]
    return args[0] if len(args) == 1 else annotation


def _allows_none(annotation: Any) -> bool:
    return get_origin(annotation) is Union and type(None) in get_args(annotation)


def _metadata_prompt(filename: str, text: str, barcode_messages: list[str]) -> str:
    return f"""
File: {filename}
Detected barcode payloads: {json.dumps(barcode_messages[:5])}
Extracted text:
{text}

Return JSON matching these fields when present:
event_type, event_name, title, description, date, time, duration, venue_name,
venue_address, city, state_country, latitude, longitude, organizer,
performer_artist, seat_info, barcode_data, price, confirmation_number,
gate_info, event_description, venue_type, capacity, website, phone,
nearby_landmarks, public_transport, parking_info, age_restriction, dress_code,
weather_considerations, amenities, accessibility, confidence_score,
multiple_events, upcoming_events, venue_place_id, performer_names, exhibit_name,
has_assigned_seating, event_urls, multiple_tickets, background_color,
foreground_color, label_color.

Use null for unknown values. Keep title under 30 characters. Use rgb(R, G, B)
strings for colors with readable contrast.
"""


def _sensible_title(text: str, fallback: str) -> str:
    lower = text.lower()
    if "boarding pass" in lower:
        return "Boarding Pass"
    if "ticket" in lower or "entrada" in lower or "billet" in lower:
        return "Event Ticket"
    if fallback and len(re.sub(r"[^A-Za-z]", "", fallback)) >= 3:
        return fallback[:30]
    return "Digital Pass"
