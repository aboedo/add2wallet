from __future__ import annotations

import asyncio
import base64
import json
import logging
import re
from datetime import datetime, timezone
from typing import Any, Union, get_args, get_origin

from openai import APIStatusError, AuthenticationError, BadRequestError, OpenAI, RateLimitError
from pydantic import ValidationError

from app.core.config import Settings
from app.core.errors import UpstreamServiceError
from app.core.models import DocumentKind, PassSegment, StructuredMetadata


logger = logging.getLogger(__name__)

# Reasoning models spend completion tokens thinking before they emit a single
# character of JSON, so these budgets cover reasoning + output, not output alone.
# Too low and the answer is truncated into a parse failure that the fallback
# silently swallows.
METADATA_TOKEN_BUDGET = 6000
SEGMENTS_TOKEN_BUDGET = 8000


class MetadataExtractor:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.client = (
            OpenAI(api_key=settings.openai_api_key, timeout=30.0)
            if settings.openai_api_key
            else None
        )

    def _log_rejected_request(self) -> None:
        """A 400 means OPENAI_MODEL and the request shape disagree.

        That is a deploy-time misconfiguration, not a blip: every extraction
        will quietly return heuristic metadata until someone notices. Log it
        loudly enough to be seen rather than letting it pass as a warning.
        """
        logger.error(
            "OpenAI rejected the request for model %r — falling back to heuristics "
            "for every document until this is fixed",
            self.settings.openai_model,
            exc_info=True,
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
                response_format={"type": "json_object"},
                max_completion_tokens=METADATA_TOKEN_BUDGET,
            )
            return _metadata_from_json(response.choices[0].message.content or "", self.settings.openai_model)
        except (AuthenticationError, RateLimitError) as exc:
            raise UpstreamServiceError("OpenAI metadata extraction is unavailable") from exc
        except BadRequestError:
            self._log_rejected_request()
            return fallback_metadata(text, filename, barcode_messages, self.settings.openai_model)
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
                response_format={"type": "json_object"},
                max_completion_tokens=METADATA_TOKEN_BUDGET,
            )
            return _metadata_from_json(response.choices[0].message.content or "", self.settings.openai_model)
        except (AuthenticationError, RateLimitError) as exc:
            raise UpstreamServiceError("OpenAI vision extraction is unavailable") from exc
        except BadRequestError:
            self._log_rejected_request()
            return fallback_metadata(fallback_text, filename, barcode_messages, self.settings.openai_model)
        except APIStatusError as exc:
            if exc.status_code in {401, 402, 429}:
                raise UpstreamServiceError("OpenAI vision extraction is unavailable") from exc
            logger.warning("OpenAI vision extraction failed; using fallback", exc_info=True)
            return fallback_metadata(fallback_text, filename, barcode_messages, self.settings.openai_model)
        except Exception:
            logger.warning("OpenAI vision extraction failed; using fallback", exc_info=True)
            return fallback_metadata(fallback_text, filename, barcode_messages, self.settings.openai_model)


    async def extract_segments(
        self,
        pages: list[str],
        filename: str,
    ) -> tuple[list[PassSegment], str | None, str | None]:
        """Pull one segment per page from a multi-part document.

        Returns (segments, group_id, group_name). Empty segments mean the
        document is a single ticket and document-level metadata is enough.
        """
        usable = [(index, text) for index, text in enumerate(pages) if text and text.strip()]
        if not self.client or len(usable) < 2:
            return [], None, None

        try:
            response = await asyncio.to_thread(
                self.client.chat.completions.create,
                model=self.settings.openai_model,
                messages=[
                    {
                        "role": "system",
                        "content": (
                            "Split multi-part travel and booking documents into their individual "
                            "legs or segments. Return JSON only."
                        ),
                    },
                    {"role": "user", "content": _segments_prompt(filename, usable)},
                ],
                response_format={"type": "json_object"},
                max_completion_tokens=SEGMENTS_TOKEN_BUDGET,
            )
            return _segments_from_json(response.choices[0].message.content or "")
        except BadRequestError:
            self._log_rejected_request()
            return [], None, None
        except (AuthenticationError, RateLimitError, APIStatusError):
            logger.info("Segment extraction unavailable", exc_info=True)
            return [], None, None
        except Exception:
            logger.warning("Segment extraction failed; falling back to document metadata", exc_info=True)
            return [], None, None


def _segments_prompt(filename: str, pages: list[tuple[int, str]]) -> str:
    body = "\n\n".join(f"--- PAGE {index} ---\n{text[:2500]}" for index, text in pages)
    return f"""
File: {filename}

{body}

This document may contain several separate tickets or bookings — for example a
multi-leg journey where each page is one leg, or a booking covering several
nights or sessions.

Return JSON:
{{
  "group_id": "shared order/booking reference, or null",
  "group_name": "short name for the whole trip or booking, or null",
  "segments": [
    {{
      "page": <the PAGE number the segment came from>,
      "label": "short human title, e.g. 'Train Bergen to Voss'",
      "origin": "...", "destination": "...",
      "depart_date": "YYYY-MM-DD", "depart_time": "HH:MM",
      "arrive_date": "YYYY-MM-DD", "arrive_time": "HH:MM",
      "carrier": "operator or provider",
      "vehicle_info": "train/flight/line number or vessel",
      "seat_info": "plain text, e.g. 'Car 1, Seats 9 and 10'",
      "travel_class": "...",
      "confirmation_number": "the reference for THIS segment",
      "traveler": "...",
      "notes": "practical info worth keeping, plain text"
    }}
  ]
}}

Only include pages that are an actual ticket or booking segment; skip cover
pages, receipts, terms and payment summaries. If the document is a single
ticket, return an empty segments array. Never output nested objects or arrays
inside a segment field — every value must be a plain string or null.
"""


def _segments_from_json(raw: str) -> tuple[list[PassSegment], str | None, str | None]:
    text = raw.strip()
    if "```json" in text:
        start = text.find("```json") + len("```json")
        text = text[start : text.find("```", start)].strip()
    elif "{" in text:
        text = text[text.find("{") : text.rfind("}") + 1]

    data = json.loads(text)
    segments: list[PassSegment] = []
    for item in data.get("segments") or []:
        if not isinstance(item, dict):
            continue
        fields = {
            key: value for key, value in item.items() if key in PassSegment.model_fields
        }
        page = fields.get("page")
        fields["page"] = page if isinstance(page, int) else None
        for key, value in list(fields.items()):
            if key != "page" and value is not None and not isinstance(value, str):
                fields[key] = _humanize(value)
        try:
            segments.append(PassSegment(**fields))
        except ValidationError:
            logger.warning("Skipping unusable segment: %s", fields)
    group_id = data.get("group_id")
    group_name = data.get("group_name")
    return (
        segments,
        group_id if isinstance(group_id, str) else None,
        group_name if isinstance(group_name, str) else None,
    )


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
            coerced[key] = _humanize(value)
            continue

        coerced[key] = value
    return coerced


def _humanize(value: Any) -> str:
    """Render a non-string value as text a person would want on a pass.

    The model answers structured fields with objects — seat_info comes back as
    {"car": 1, "seats": [9, 10]} — and a bare str() leaked the Python repr
    ("{'car': 1, 'seats': [9, 10]}") straight onto the pass.
    """
    if isinstance(value, dict):
        parts = [
            f"{str(key).replace('_', ' ').strip().capitalize()} {_humanize(item)}"
            for key, item in value.items()
            if item not in (None, "", [], {})
        ]
        return ", ".join(parts)
    if isinstance(value, (list, tuple, set)):
        return ", ".join(_humanize(item) for item in value if item not in (None, ""))
    if isinstance(value, bool):
        return "Yes" if value else "No"
    return str(value)


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
event_type, event_name, title, description, date, time, end_date, end_time, duration, venue_name,
venue_address, city, state_country, latitude, longitude, organizer,
performer_artist, seat_info, barcode_data, price, confirmation_number,
gate_info, event_description, venue_type, capacity, website, phone,
nearby_landmarks, public_transport, parking_info, age_restriction, dress_code,
weather_considerations, amenities, accessibility, confidence_score,
multiple_events, upcoming_events, venue_place_id, performer_names, exhibit_name,
has_assigned_seating, event_urls, multiple_tickets, brand_color, background_color,
foreground_color, label_color.

Use null for unknown values. Keep title under 30 characters. Use rgb(R, G, B)
strings for colors with readable contrast. confidence_score is an integer from
0 to 100, not a fraction. event_urls is an object mapping a label to a URL,
e.g. {{"tickets": "https://..."}}.

brand_color is the one field you may reason about rather than copy: it becomes
the background of the Wallet pass. Give it as hex #RRGGBB. Prefer the
well-known brand colour of the issuing organization, venue, team, airline or
event (a club's kit, an airline's livery, a museum's identity); failing that, a
colour that suits this specific subject matter. Two different documents should
rarely land on the same colour, so do not fall back on a generic red or blue —
reach for the whole spectrum. It must be a deep, saturated colour that white
text can sit on: no greys, pastels, near-white or near-black. Use null only if
the document gives you nothing to go on.

Dates must be YYYY-MM-DD and times HH:MM (24h). Boarding passes often print a
day and month with no year ("18 Mar"): infer the year from any other date in
the document, and otherwise from the booking or issue date. A pass with a
complete date is far more useful than a null, so only give up if there is no
day or month either.

For a document that covers a
range — a hotel stay, a car rental, a multi-day pass — put the start in
date/time (check-in, pick-up) and the end in end_date/end_time (check-out,
drop-off). A document without any barcode is still valid: it is a reservation
or confirmation worth remembering, so extract every useful detail (address,
phone, confirmation number, price, what is included, cancellation terms).
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
