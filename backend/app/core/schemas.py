"""Strict JSON Schemas for the OpenAI structured-output calls.

Reasoning models reject ``temperature``, so the shape we ask for is the only
lever we have over how far two near-identical documents drift apart. Under
``{"type": "json_object"}`` the model chose its own field set and its own
spelling for every value on every call: the same concert ticket came back as
``event_type`` "concert", "concert_ticket" or "Concert Ticket", and only the
first of those selects an ``eventTicket`` pass in ``pass_builder`` — so a
wording the model picked by chance decided what the pass looked like.

These schemas go out with ``strict: true``, which is enforced during sampling
rather than checked afterwards, so the field set, the types and the
``event_type`` vocabulary stop being the model's choice.

Strict mode has three rules that shape everything below:

* every property must appear in ``required`` — "optional" is expressed as a
  nullable type, which is why almost every field here accepts null;
* every object must set ``additionalProperties: false``;
* free-form maps are not expressible, so ``event_urls`` is asked for with the
  fixed keys the client actually decodes rather than as a label→URL map.

Fields the server owns (``ai_processed``, ``processing_timestamp``,
``model_used``, ``enrichment_completed``) are deliberately absent: asking the
model for them invited it to contradict us.
"""

from __future__ import annotations

from typing import Any


# The vocabulary `pass_builder` already understands. `_type_label` matches on a
# substring precisely because the model used to invent variants like
# "hotel_booking"; the pass-style test at pass_builder.py is an exact set
# match, so a variant silently produced a generic pass instead of an event one.
EVENT_TYPES = (
    "concert",
    "sports",
    "museum",
    "attraction",
    "theater",
    "festival",
    "event_ticket",
    "movie",
    "conference",
    "flight",
    "train",
    "ferry",
    "bus",
    "hotel",
    "car_rental",
    "restaurant",
    "parking",
    "tour",
    "reservation",
    "other",
)


def _nullable(kind: str, description: str = "", **extra: Any) -> dict[str, Any]:
    schema: dict[str, Any] = {"type": [kind, "null"]}
    if description:
        schema["description"] = description
    schema.update(extra)
    return schema


def _nullable_str_array(description: str = "") -> dict[str, Any]:
    return _nullable("array", description, items={"type": "string"})


def _object(properties: dict[str, Any]) -> dict[str, Any]:
    """A strict object: closed, with every property required."""
    return {
        "type": "object",
        "properties": properties,
        "required": list(properties),
        "additionalProperties": False,
    }


# Matches app.models.responses.EventURLs — the shape the iOS client decodes.
# The old prompt asked for an arbitrary label→URL map, so whatever the model
# answered decoded to a struct of nulls on the device.
_EVENT_URLS = _object(
    {
        "parking_info_url": _nullable("string"),
        "merchandise_url": _nullable("string"),
        "venue_info_url": _nullable("string"),
        "ticket_transfer_url": _nullable("string"),
        "food_ordering_url": _nullable("string"),
    }
)

# Matches app.models.responses.UpcomingEvent. `id` is non-optional there, so a
# model-invented event without one failed to decode on the device and took the
# whole metadata payload down with it.
_UPCOMING_EVENT = _object(
    {
        "id": {"type": "string", "description": "Stable slug for this event, e.g. 'coldplay-2026-04-03'."},
        "name": {"type": "string"},
        "date": _nullable("string", "YYYY-MM-DD."),
        "venue_name": _nullable("string"),
        "latitude": _nullable("number"),
        "longitude": _nullable("number"),
        "seat_info": _nullable("string"),
        "performer_artist": _nullable("string"),
        "event_type": _nullable("string"),
    }
)


METADATA_SCHEMA = _object(
    {
        "event_type": {
            "type": "string",
            "enum": list(EVENT_TYPES),
            "description": (
                "Closest match from the list. A hotel booking is 'hotel', a rail "
                "ticket 'train', a car hire 'car_rental' — never a variant spelling."
            ),
        },
        "event_name": _nullable(
            "string",
            "What the document is for, as printed and no longer: the operator "
            "and number for a journey ('Etihad Airways EY101'), the act or "
            "match for an event. Never a sentence built around it.",
        ),
        "title": {
            "type": "string",
            "description": (
                "Pass headline, under 30 characters, phrased by the rule in the "
                "instructions: 'AUH → MAD' for a journey, the act or match for "
                "an event, the name of the place for a visit or stay."
            ),
        },
        "description": _nullable("string"),
        "date": _nullable("string", "Start date, YYYY-MM-DD."),
        "time": _nullable("string", "Start time, HH:MM in 24h, local and unconverted."),
        "end_date": _nullable("string", "Check-out / drop-off / last day, YYYY-MM-DD."),
        "end_time": _nullable("string", "HH:MM in 24h."),
        "duration": _nullable("string"),
        "venue_name": _nullable(
            "string",
            "Where the holder physically goes: the departure airport or station "
            "for a journey, the stadium/museum/cinema for an event, the property "
            "for a stay.",
        ),
        "venue_address": _nullable("string"),
        "city": _nullable("string", "The city the venue is in — for a journey, the origin."),
        "state_country": _nullable("string"),
        "latitude": _nullable("number"),
        "longitude": _nullable("number"),
        "organizer": _nullable("string"),
        "performer_artist": _nullable("string"),
        "seat_info": _nullable(
            "string",
            "The designation exactly as printed and nothing else: '31A', "
            "'Car 1, Seats 9 and 10'. Never the word 'Seat', a class, or a row label.",
        ),
        "barcode_data": _nullable("string"),
        "price": _nullable("string"),
        "gate_info": _nullable("string"),
        "event_description": _nullable("string"),
        "venue_type": _nullable("string"),
        "capacity": _nullable("string"),
        "website": _nullable("string"),
        "phone": _nullable("string"),
        "nearby_landmarks": _nullable_str_array(),
        "public_transport": _nullable("string"),
        "parking_info": _nullable("string"),
        "age_restriction": _nullable("string"),
        "dress_code": _nullable("string"),
        "weather_considerations": _nullable("string"),
        "amenities": _nullable_str_array(),
        "accessibility": _nullable("string"),
        "confidence_score": _nullable("integer", "0-100, an integer, not a fraction."),
        "brand_color": _nullable(
            "string",
            "Hex #RRGGBB, deep enough for white text. The issuer's own brand "
            "colour, so the same issuer always yields the same value.",
        ),
        "confirmation_number": _nullable(
            "string",
            "The booking reference the traveller would quote — never a flight, "
            "train or seat number.",
        ),
        "background_color": _nullable("string", "rgb(R, G, B)."),
        "foreground_color": _nullable("string", "rgb(R, G, B)."),
        "label_color": _nullable("string", "rgb(R, G, B)."),
        "multiple_events": {"type": "boolean"},
        "upcoming_events": _nullable("array", items=_UPCOMING_EVENT),
        "venue_place_id": _nullable("string"),
        "performer_names": _nullable_str_array(),
        "exhibit_name": _nullable("string"),
        "has_assigned_seating": {"type": "boolean"},
        "event_urls": {
            "anyOf": [_EVENT_URLS, {"type": "null"}],
            "description": "Only URLs the document actually gives.",
        },
        "multiple_tickets": {"type": "boolean"},
        "group_name": _nullable(
            "string",
            "Name for the whole set when this document is worth several passes; "
            "null for a single ticket. Under 40 characters.",
        ),
    }
)


_SEGMENT = _object(
    {
        "page": _nullable("integer", "The PAGE number this segment came from."),
        "label": _nullable("string", "Short human title, e.g. 'Train Bergen to Voss'."),
        "origin": _nullable("string"),
        "destination": _nullable("string"),
        "depart_date": _nullable("string", "YYYY-MM-DD."),
        "depart_time": _nullable("string", "HH:MM in 24h, exactly as printed."),
        "arrive_date": _nullable("string", "YYYY-MM-DD."),
        "arrive_time": _nullable("string", "HH:MM in 24h, exactly as printed."),
        "depart_timezone": _nullable(
            "string", "IANA zone of the ORIGIN, e.g. 'Europe/Oslo'. Never an offset."
        ),
        "arrive_timezone": _nullable("string", "IANA zone of the DESTINATION. Never an offset."),
        "carrier": _nullable("string"),
        "vehicle_info": _nullable("string", "Train/flight/line number or vessel."),
        "seat_info": _nullable("string", "Plain text."),
        "travel_class": _nullable("string"),
        "confirmation_number": _nullable("string", "The reference for THIS segment."),
        "traveler": _nullable("string"),
        "traveler_count": _nullable("integer", "People on this leg: the 2 in '2 x Adult'."),
        "notes": _nullable("string", "Practical info worth keeping, plain text."),
    }
)


SEGMENTS_SCHEMA = _object(
    {
        "group_id": _nullable("string", "Shared order/booking reference."),
        "group_name": _nullable("string", "Short name for the whole trip or booking."),
        "segments": {
            "type": "array",
            "items": _SEGMENT,
            "description": "Empty when the document is a single ticket.",
        },
    }
)


def response_format(name: str, schema: dict[str, Any]) -> dict[str, Any]:
    return {
        "type": "json_schema",
        "json_schema": {"name": name, "strict": True, "schema": schema},
    }


METADATA_RESPONSE_FORMAT = response_format("wallet_pass_metadata", METADATA_SCHEMA)
SEGMENTS_RESPONSE_FORMAT = response_format("wallet_pass_segments", SEGMENTS_SCHEMA)

# What we fall back to when the deployed model turns out not to support strict
# schemas. Losing the shape guarantee is bad; losing every extraction to
# heuristics because of it is worse.
JSON_OBJECT_RESPONSE_FORMAT = {"type": "json_object"}
