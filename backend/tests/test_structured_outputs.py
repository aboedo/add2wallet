"""Guards on the strict response schemas.

The schemas are hand-written rather than generated from the Pydantic models,
because what we want the model to answer is not quite what we store. That buys
readable field descriptions at the cost of a second place to forget, so these
tests hold the two in sync: a field added to StructuredMetadata and not to the
schema would simply never be extracted again, silently.

They also hold the schemas to OpenAI's strict-mode rules, which are enforced
with a 400 rather than a warning — and a 400 here costs every extraction.
"""

import dataclasses
import logging
from datetime import date
from unittest.mock import MagicMock

import pytest
from openai import BadRequestError

from app.core.config import get_settings
from app.core.metadata import MetadataExtractor, _metadata_from_json, _metadata_prompt
from app.core.models import PassSegment, StructuredMetadata
from app.core.schemas import (
    EVENT_TYPES,
    METADATA_RESPONSE_FORMAT,
    METADATA_SCHEMA,
    SEGMENTS_SCHEMA,
)

# Set by the server after the call, so asking the model for them only invited
# it to disagree with us.
SERVER_OWNED = {"ai_processed", "processing_timestamp", "model_used", "enrichment_completed"}


@pytest.fixture
def extractor():
    settings = dataclasses.replace(get_settings(), openai_api_key="test-key")
    instance = MetadataExtractor(settings)
    instance.client = MagicMock()
    return instance


def _completion(content: str) -> MagicMock:
    response = MagicMock()
    response.choices = [MagicMock()]
    response.choices[0].message.content = content
    response.choices[0].message.refusal = None
    return response


def _bad_request(message: str = "Invalid schema") -> BadRequestError:
    response = MagicMock()
    response.status_code = 400
    response.headers = {}
    return BadRequestError(message=message, response=response, body=None)


def _objects(schema: dict) -> list[dict]:
    """Every object node in a schema, including nested ones."""
    found = []
    if isinstance(schema, dict):
        if schema.get("type") == "object":
            found.append(schema)
        for value in schema.values():
            found.extend(_objects(value))
    elif isinstance(schema, list):
        for item in schema:
            found.extend(_objects(item))
    return found


class TestStrictModeRules:
    @pytest.mark.parametrize("schema", [METADATA_SCHEMA, SEGMENTS_SCHEMA])
    def test_every_object_is_closed_and_fully_required(self, schema):
        """Strict mode rejects an open object, or one with an optional key."""
        for node in _objects(schema):
            assert node.get("additionalProperties") is False
            assert set(node["required"]) == set(node["properties"])

    @pytest.mark.parametrize("schema", [METADATA_SCHEMA, SEGMENTS_SCHEMA])
    def test_no_free_form_maps(self, schema):
        """`additionalProperties: true` is how a label→URL map would sneak in."""
        for node in _objects(schema):
            assert node["properties"], "an object with no properties is a map in disguise"


class TestSchemaMatchesTheModel:
    def test_metadata_fields_all_exist_on_structured_metadata(self):
        unknown = set(METADATA_SCHEMA["properties"]) - set(StructuredMetadata.model_fields)
        assert not unknown, f"asking the model for fields we do not store: {sorted(unknown)}"

    def test_every_storable_field_is_asked_for(self):
        missing = set(StructuredMetadata.model_fields) - set(METADATA_SCHEMA["properties"]) - SERVER_OWNED
        assert not missing, f"fields we store but no longer extract: {sorted(missing)}"

    def test_segment_fields_all_exist_on_pass_segment(self):
        properties = SEGMENTS_SCHEMA["properties"]["segments"]["items"]["properties"]
        assert set(properties) == set(PassSegment.model_fields)


class TestEventTypeVocabulary:
    def test_covers_the_types_that_select_an_event_ticket_pass(self):
        """pass_builder matches this set exactly, so a variant spelling
        ("concert_ticket") quietly produced a generic pass instead."""
        event_ticket_types = {
            "concert",
            "sports",
            "museum",
            "attraction",
            "theater",
            "festival",
            "event_ticket",
        }
        assert event_ticket_types <= set(EVENT_TYPES)

    def test_enum_is_what_we_send(self):
        assert METADATA_SCHEMA["properties"]["event_type"]["enum"] == list(EVENT_TYPES)

    def test_travel_and_stay_types_survive(self):
        assert {"flight", "train", "ferry", "bus", "hotel", "car_rental"} <= set(EVENT_TYPES)


class TestSchemaRejectionDegradesRatherThanCollapses:
    @pytest.mark.asyncio
    async def test_retries_in_plain_json_mode(self, extractor, caplog):
        """A model that cannot do strict schemas must still produce metadata."""
        extractor.client.chat.completions.create.side_effect = [
            _bad_request("response_format json_schema is not supported"),
            _completion('{"title": "Rescued", "event_type": "concert"}'),
        ]

        with caplog.at_level(logging.WARNING, logger="app.core.metadata"):
            metadata = await extractor.extract_from_text("ticket", "t.pdf", [])

        assert metadata.title == "Rescued"
        assert metadata.ai_processed is True, "the retry is a real extraction, not a fallback"
        formats = [
            call.kwargs["response_format"]
            for call in extractor.client.chat.completions.create.call_args_list
        ]
        assert formats[0] == METADATA_RESPONSE_FORMAT
        assert formats[1] == {"type": "json_object"}
        assert any(record.levelno >= logging.WARNING for record in caplog.records)

    @pytest.mark.asyncio
    async def test_a_second_rejection_falls_back_to_heuristics(self, extractor):
        extractor.client.chat.completions.create.side_effect = _bad_request()

        metadata = await extractor.extract_from_text("boarding pass", "t.pdf", [])

        assert metadata.ai_processed is False
        assert extractor.client.chat.completions.create.call_count == 2


class TestRefusal:
    @pytest.mark.asyncio
    async def test_refusal_is_not_read_as_an_empty_answer(self, extractor):
        """A refusal arrives with content=None, which would otherwise look like
        a parse failure and be logged as one."""
        refused = _completion("")
        refused.choices[0].message.content = None
        refused.choices[0].message.refusal = "I cannot help with that."
        extractor.client.chat.completions.create.return_value = refused

        metadata = await extractor.extract_from_text("ticket", "t.pdf", [])

        assert metadata.ai_processed is False


class TestTheYearIsAnchored:
    """A boarding pass that prints "18 Mar" and no year anywhere was the single
    worst source of drift we measured: asked to guess, the model answered 2025,
    2026 and 2027 for the same file on consecutive runs. Stating today's date
    turns the guess into a rule with one answer."""

    def test_prompt_states_today(self):
        prompt = _metadata_prompt("bp.pdf", "18 Mar", [], today=date(2026, 8, 15))

        assert "2026-08-15" in prompt

    def test_prompt_asks_for_the_next_occurrence(self):
        prompt = " ".join(_metadata_prompt("bp.pdf", "18 Mar", [], today=date(2026, 8, 15)).split())

        assert "on or after today" in prompt

    def test_a_document_year_still_wins(self):
        """Anchoring is the fallback, not the first move — a year printed on the
        document is the truth even when it is in the past."""
        prompt = " ".join(_metadata_prompt("bp.pdf", "18 Mar", [], today=date(2026, 8, 15)).split())

        assert "Take the year from another date printed" in prompt


class TestNestedFieldsAreCleanedUp:
    def test_all_null_url_block_becomes_none(self):
        """Strict mode requires every key, so "no links" arrives as five nulls."""
        raw = '{"title": "T", "event_urls": {"parking_info_url": null, "merchandise_url": null}}'

        metadata = _metadata_from_json(raw, "gpt-5.6-luna")

        assert metadata.event_urls is None

    def test_real_urls_survive_without_their_nulls(self):
        raw = '{"title": "T", "event_urls": {"parking_info_url": "https://p", "merchandise_url": null}}'

        metadata = _metadata_from_json(raw, "gpt-5.6-luna")

        assert metadata.event_urls == {"parking_info_url": "https://p"}

    def test_upcoming_event_without_an_id_is_dropped(self):
        """The client's UpcomingEvent requires id and name; one entry missing
        either failed to decode and took the whole metadata payload down."""
        raw = (
            '{"title": "T", "upcoming_events": ['
            '{"id": null, "name": "Night 2"},'
            '{"id": "night-3", "name": "Night 3", "venue_name": null}]}'
        )

        metadata = _metadata_from_json(raw, "gpt-5.6-luna")

        assert metadata.upcoming_events == [{"id": "night-3", "name": "Night 3"}]

    def test_empty_upcoming_events_becomes_none(self):
        metadata = _metadata_from_json('{"title": "T", "upcoming_events": []}', "gpt-5.6-luna")

        assert metadata.upcoming_events is None
