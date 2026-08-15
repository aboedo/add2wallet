from __future__ import annotations

import asyncio
import base64
import json
import logging
import re
from datetime import date, datetime, timezone
from typing import Any, Union, get_args, get_origin

from openai import APIStatusError, AuthenticationError, BadRequestError, OpenAI, RateLimitError
from pydantic import ValidationError

from app.core.config import Settings
from app.core.errors import UpstreamServiceError
from app.core.models import DocumentKind, PassSegment, StructuredMetadata
from app.core.schemas import (
    JSON_OBJECT_RESPONSE_FORMAT,
    METADATA_RESPONSE_FORMAT,
    SEGMENTS_RESPONSE_FORMAT,
)


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

    def _complete_json(
        self,
        messages: list[dict[str, Any]],
        response_format: dict[str, Any],
        max_completion_tokens: int,
    ) -> str:
        """Ask for JSON, degrading to plain JSON mode if the schema is rejected.

        The strict schema is what stops two near-identical documents becoming
        two different passes, but it is newer than some models that could be
        deployed here. Left alone, a 400 would send every document to the regex
        heuristics; one retry without the schema keeps extraction working, and
        the warning says which of the two shapes actually went out.
        """
        try:
            response = self.client.chat.completions.create(
                model=self.settings.openai_model,
                messages=messages,
                response_format=response_format,
                max_completion_tokens=max_completion_tokens,
            )
        except BadRequestError:
            if response_format is JSON_OBJECT_RESPONSE_FORMAT:
                raise
            logger.warning(
                "Model %r rejected the strict schema; retrying in plain JSON mode, "
                "so this extraction is unconstrained",
                self.settings.openai_model,
                exc_info=True,
            )
            response = self.client.chat.completions.create(
                model=self.settings.openai_model,
                messages=messages,
                response_format=JSON_OBJECT_RESPONSE_FORMAT,
                max_completion_tokens=max_completion_tokens,
            )

        message = response.choices[0].message
        # A refusal comes back with content=None, which would otherwise read as
        # an empty answer and be blamed on a parse failure.
        refusal = getattr(message, "refusal", None)
        if isinstance(refusal, str) and refusal.strip():
            raise ValueError(f"Model refused the extraction: {refusal}")
        return message.content or ""

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
            content = await asyncio.to_thread(
                self._complete_json,
                [
                    {
                        "role": "system",
                        "content": "Extract Apple Wallet pass metadata from tickets, receipts, bookings, and travel documents.",
                    },
                    {"role": "user", "content": prompt},
                ],
                METADATA_RESPONSE_FORMAT,
                METADATA_TOKEN_BUDGET,
            )
            return _metadata_from_json(content, self.settings.openai_model)
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
            answer = await asyncio.to_thread(
                self._complete_json,
                [
                    {
                        "role": "system",
                        "content": "Extract Apple Wallet pass metadata from ticket images.",
                    },
                    {"role": "user", "content": content},
                ],
                METADATA_RESPONSE_FORMAT,
                METADATA_TOKEN_BUDGET,
            )
            return _metadata_from_json(answer, self.settings.openai_model)
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
            content = await asyncio.to_thread(
                self._complete_json,
                [
                    {
                        "role": "system",
                        "content": (
                            "Split multi-part travel and booking documents into their individual "
                            "legs or segments."
                        ),
                    },
                    {"role": "user", "content": _segments_prompt(filename, usable)},
                ],
                SEGMENTS_RESPONSE_FORMAT,
                SEGMENTS_TOKEN_BUDGET,
            )
            return _segments_from_json(content)
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

Only include pages that are an actual ticket or booking segment; skip cover
pages, receipts, terms and payment summaries. If the document is a single
ticket, return an empty segments array.

Times are local to the place they happen, so leave them exactly as printed and
never convert them. Say where they are local to in the timezone fields, as an
IANA zone name like "Europe/Oslo" — never an offset like "+02:00", which is
only true for half the year. Give a zone when the document states one or when
the place identifies it beyond doubt (an airport code, a station, a named
city), and null when it is ambiguous: a wrong zone silently moves every time on
the itinerary, so do not guess.

"traveler_count" is the number of people on that leg, not the number of codes
printed. A leg that says "2 x Adult" is two tickets whether it shows two
barcodes, one shared barcode, or none at all.
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
    data["event_urls"] = _drop_empty(data.get("event_urls"))
    data["upcoming_events"] = _prune_upcoming_events(data.get("upcoming_events"))
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


def _drop_empty(value: Any) -> dict[str, Any] | None:
    """Strip the nulls out of a nested object, and drop it if nothing is left.

    A strict schema requires every key, so the model answers the URL block with
    five nulls for the many documents that carry no links at all. Storing that
    turns "we found nothing" into an object the client has to interpret.
    """
    if not isinstance(value, dict):
        return None
    kept = {key: item for key, item in value.items() if item not in (None, "", [], {})}
    return kept or None


def _prune_upcoming_events(value: Any) -> list[dict[str, Any]] | None:
    if not isinstance(value, list):
        return None
    # `id` and `name` are the two the client requires; an entry without them
    # fails to decode on the device and takes the whole payload with it.
    kept = [
        pruned
        for pruned in (_drop_empty(item) for item in value)
        if pruned and pruned.get("id") and pruned.get("name")
    ]
    return kept or None


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


def _metadata_prompt(
    filename: str,
    text: str,
    barcode_messages: list[str],
    today: date | None = None,
) -> str:
    """Build the extraction prompt.

    ``today`` is stated rather than left implicit because boarding passes
    routinely print "18 Mar" and no year at all. Asked to guess, the model
    answered 2025, 2026 and 2027 for the same file on consecutive runs — the
    single worst source of drift we measured. Given the date, the rule
    ("the next 18 Mar from here") lands on one answer.
    """
    today = today or date.today()
    return f"""
File: {filename}
Detected barcode payloads: {json.dumps(barcode_messages[:5])}
Extracted text:
{text}

Fill in the schema from the document. Read what is printed, and work out what
it implies — an airport code names a city, a flight number names an airline, a
day and month imply a year. Only use null when the document leaves you with
nothing to work from; a field you could have inferred is worse left empty.

Two people given this same document should write down the same answers, so
where a rule below says how to phrase a field, follow it exactly rather than
finding your own wording.

title is the pass headline, under 30 characters:
  * a journey is "ORIGIN → DESTINATION", using the airport or station codes
    whenever the document prints them ("AUH → MAD") and the place names only
    when it does not ("Bergen → Voss");
  * an event is the act or match: "Coldplay", "Peñarol v Nacional";
  * a place you visit is its name: "Museo Reina Sofía";
  * a stay or a booking is the property or restaurant name.
Do not put the operator, the word "ticket", or a booking reference in it.

venue_name is where the holder physically goes to use this: the departure
airport or station for a journey, the stadium, museum, cinema or theatre for an
event, the property for a stay. city is the city that venue is in — for a
journey, the origin city, not the destination.

brand_color becomes the background of the Wallet pass. Give it as hex #RRGGBB.
Use the actual brand colour of whoever issues the document — the airline's
livery, the club's kit, the museum's identity — so that two documents from the
same issuer always come out the same colour. If the issuer has no colour you
know, pick one from the subject matter, and avoid a generic red or blue. It
must be deep and saturated enough for white text to sit on: no greys, pastels,
near-white or near-black. Use null only if the document gives you nothing to go
on. Colors other than brand_color are rgb(R, G, B) with readable contrast.

"group_name" is what to call the document as a whole when it is worth several
passes — several tickets to one show, the legs of one journey, the nights of
one booking. Name the set, never one of its members: "Coldplay at Wembley", not
"General Admission"; "Norway in a Nutshell", not "Train Bergen to Voss". Keep it
under 40 characters, and use null for a single ticket or when the set has no
name beyond what its members already say.

Times on a ticket are local to the place they happen, so leave them exactly as
printed and never convert them to another zone.

Dates must be YYYY-MM-DD and times HH:MM (24h). Boarding passes often print a
day and month with no year ("18 Mar"). Take the year from another date printed
on the document — the issue date, the booking date, the return leg. When the
document prints no year at all, use the next time that day and month occur on
or after today, {today}: an undated boarding pass is for the journey ahead, not
the one last year. Only give up when there is no day or month either.

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
