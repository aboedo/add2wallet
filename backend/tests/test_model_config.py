"""Guards on how we call the OpenAI chat API.

Reasoning models reject `temperature` and `max_tokens` outright. Because every
extraction path swallows failures into heuristic metadata, sending a rejected
parameter does not raise — it silently makes every pass worse. These tests keep
the request shape honest.
"""

import dataclasses
import logging
from unittest.mock import MagicMock

import pytest
from openai import BadRequestError

from app.core.config import get_settings
from app.core.metadata import METADATA_TOKEN_BUDGET, SEGMENTS_TOKEN_BUDGET, MetadataExtractor

# Parameters the chat/completions API rejects on reasoning models.
REJECTED_PARAMS = ("temperature", "max_tokens", "top_p", "frequency_penalty", "presence_penalty")


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
    return response


def _bad_request() -> BadRequestError:
    response = MagicMock()
    response.status_code = 400
    response.headers = {}
    return BadRequestError(
        message="Unsupported parameter: 'max_tokens' is not supported with this model.",
        response=response,
        body=None,
    )


class TestDefaultModel:
    def test_default_is_a_gpt_5_model(self, monkeypatch):
        monkeypatch.delenv("OPENAI_MODEL", raising=False)
        assert get_settings().openai_model.startswith("gpt-5")

    def test_env_still_overrides(self, monkeypatch):
        monkeypatch.setenv("OPENAI_MODEL", "gpt-4o-mini")
        assert get_settings().openai_model == "gpt-4o-mini"


class TestRequestShape:
    @pytest.mark.asyncio
    async def test_text_extraction_sends_no_rejected_params(self, extractor):
        extractor.client.chat.completions.create.return_value = _completion('{"title": "T"}')

        await extractor.extract_from_text("ticket text", "t.pdf", [])

        kwargs = extractor.client.chat.completions.create.call_args.kwargs
        for param in REJECTED_PARAMS:
            assert param not in kwargs, f"{param} is rejected by reasoning models"
        assert kwargs["max_completion_tokens"] == METADATA_TOKEN_BUDGET

    @pytest.mark.asyncio
    async def test_vision_extraction_sends_no_rejected_params(self, extractor):
        extractor.client.chat.completions.create.return_value = _completion('{"title": "T"}')

        await extractor.extract_from_vision([(b"img", "image/png")], "t.png", [])

        kwargs = extractor.client.chat.completions.create.call_args.kwargs
        for param in REJECTED_PARAMS:
            assert param not in kwargs
        assert kwargs["max_completion_tokens"] == METADATA_TOKEN_BUDGET

    @pytest.mark.asyncio
    async def test_segment_extraction_sends_no_rejected_params(self, extractor):
        extractor.client.chat.completions.create.return_value = _completion('{"segments": []}')

        await extractor.extract_segments(["page one", "page two"], "t.pdf")

        kwargs = extractor.client.chat.completions.create.call_args.kwargs
        for param in REJECTED_PARAMS:
            assert param not in kwargs
        assert kwargs["max_completion_tokens"] == SEGMENTS_TOKEN_BUDGET

    @pytest.mark.asyncio
    async def test_json_mode_is_requested(self, extractor):
        """The parsers strip markdown fences, but asking for JSON is cheaper."""
        extractor.client.chat.completions.create.return_value = _completion('{"title": "T"}')

        await extractor.extract_from_text("ticket text", "t.pdf", [])

        kwargs = extractor.client.chat.completions.create.call_args.kwargs
        assert kwargs["response_format"] == {"type": "json_object"}

    def test_token_budget_leaves_room_for_reasoning(self):
        """Reasoning burns completion tokens before any JSON is emitted."""
        assert METADATA_TOKEN_BUDGET >= 4000
        assert SEGMENTS_TOKEN_BUDGET >= METADATA_TOKEN_BUDGET


class TestRejectedRequestIsLoud:
    @pytest.mark.asyncio
    async def test_bad_request_falls_back_but_logs_an_error(self, extractor, caplog):
        extractor.client.chat.completions.create.side_effect = _bad_request()

        with caplog.at_level(logging.ERROR, logger="app.core.metadata"):
            metadata = await extractor.extract_from_text("ticket text", "t.pdf", [])

        assert metadata is not None, "a rejected request must still return usable metadata"
        assert any(
            record.levelno >= logging.ERROR and extractor.settings.openai_model in record.getMessage()
            for record in caplog.records
        ), "a model misconfiguration must name the model at ERROR level"

    @pytest.mark.asyncio
    async def test_bad_request_on_segments_is_not_silent(self, extractor, caplog):
        extractor.client.chat.completions.create.side_effect = _bad_request()

        with caplog.at_level(logging.ERROR, logger="app.core.metadata"):
            segments, group_id, group_name = await extractor.extract_segments(["a", "b"], "t.pdf")

        assert segments == []
        assert any(record.levelno >= logging.ERROR for record in caplog.records)
