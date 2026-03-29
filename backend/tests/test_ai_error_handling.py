"""Tests for AI service error handling and transport classification prompt.

These tests verify:
1. AIServiceError is raised (not swallowed) for billing/auth/rate-limit errors
2. JSON parse errors still fall back gracefully
3. The transport classification prompt includes ferry/bus/train guidance
4. The prompt does NOT hardcode specific company names
"""
import pytest
import os
import sys
import json
from unittest.mock import patch, MagicMock

# Add backend to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from app.services.ai_service import AIService, AIServiceError


class TestAIServiceErrorClass:
    """Test that AIServiceError exists and is properly defined."""

    def test_ai_service_error_is_exception(self):
        assert issubclass(AIServiceError, Exception)

    def test_ai_service_error_message(self):
        err = AIServiceError("credits exhausted")
        assert str(err) == "credits exhausted"


class TestAIServiceErrorHandling:
    """Test that OpenAI API errors are properly raised, not swallowed."""

    def setup_method(self):
        self.service = AIService.__new__(AIService)
        self.service.ai_enabled = True
        self.service.client = MagicMock()

    @pytest.mark.asyncio
    async def test_authentication_error_raises_ai_service_error(self):
        """AuthenticationError (invalid key, expired credits) should raise AIServiceError."""
        from openai import AuthenticationError

        mock_response = MagicMock()
        mock_response.status_code = 401
        mock_response.headers = {}

        self.service.client.chat.completions.create.side_effect = AuthenticationError(
            message="Incorrect API key provided",
            response=mock_response,
            body=None
        )

        with pytest.raises(AIServiceError, match="AI service unavailable"):
            await self.service._extract_pdf_metadata("some pdf text", "test.pdf")

    @pytest.mark.asyncio
    async def test_rate_limit_error_raises_ai_service_error(self):
        """RateLimitError should raise AIServiceError."""
        from openai import RateLimitError

        mock_response = MagicMock()
        mock_response.status_code = 429
        mock_response.headers = {}

        self.service.client.chat.completions.create.side_effect = RateLimitError(
            message="Rate limit exceeded",
            response=mock_response,
            body=None
        )

        with pytest.raises(AIServiceError, match="AI service unavailable"):
            await self.service._extract_pdf_metadata("some pdf text", "test.pdf")

    @pytest.mark.asyncio
    async def test_api_status_error_402_raises_ai_service_error(self):
        """402 Payment Required should raise AIServiceError."""
        from openai import APIStatusError

        mock_response = MagicMock()
        mock_response.status_code = 402
        mock_response.headers = {}

        self.service.client.chat.completions.create.side_effect = APIStatusError(
            message="Payment required",
            response=mock_response,
            body=None
        )

        with pytest.raises(AIServiceError, match="AI service unavailable"):
            await self.service._extract_pdf_metadata("some pdf text", "test.pdf")

    @pytest.mark.asyncio
    async def test_api_status_error_500_falls_back(self):
        """500 Internal Server Error should fall back, not raise AIServiceError."""
        from openai import APIStatusError

        mock_response = MagicMock()
        mock_response.status_code = 500
        mock_response.headers = {}

        self.service.client.chat.completions.create.side_effect = APIStatusError(
            message="Internal server error",
            response=mock_response,
            body=None
        )

        result = await self.service._extract_pdf_metadata("Concert ticket\n2026-04-15", "concert.pdf")
        assert result is not None
        assert result.get("fallback_used") is True

    @pytest.mark.asyncio
    async def test_billing_keyword_in_generic_exception_raises(self):
        """Generic exceptions mentioning billing/credits should raise AIServiceError."""
        self.service.client.chat.completions.create.side_effect = Exception(
            "You exceeded your current quota, please check your plan and billing details."
        )

        with pytest.raises(AIServiceError, match="AI service unavailable"):
            await self.service._extract_pdf_metadata("some text", "test.pdf")

    @pytest.mark.asyncio
    async def test_generic_exception_without_billing_falls_back(self):
        """Generic exceptions NOT related to billing should fall back gracefully."""
        self.service.client.chat.completions.create.side_effect = Exception(
            "Connection timeout"
        )

        result = await self.service._extract_pdf_metadata("Concert ticket\n2026-04-15", "test.pdf")
        assert result is not None
        assert result.get("fallback_used") is True

    @pytest.mark.asyncio
    async def test_json_parse_error_falls_back(self):
        """Invalid JSON from OpenAI should fall back, not raise."""
        mock_response = MagicMock()
        mock_response.choices = [MagicMock()]
        mock_response.choices[0].message.content = "This is not valid JSON at all"
        self.service.client.chat.completions.create.return_value = mock_response

        result = await self.service._extract_pdf_metadata("Concert ticket", "test.pdf")
        assert result is not None
        assert result.get("fallback_used") is True


class TestAIServiceErrorPropagation:
    """Test that AIServiceError propagates through analyze_pdf_content."""

    def setup_method(self):
        self.service = AIService.__new__(AIService)
        self.service.ai_enabled = True
        self.service.client = MagicMock()

    @pytest.mark.asyncio
    async def test_analyze_pdf_content_propagates_ai_service_error(self):
        """AIServiceError from _extract_pdf_metadata should propagate through analyze_pdf_content."""
        from openai import AuthenticationError

        mock_response = MagicMock()
        mock_response.status_code = 401
        mock_response.headers = {}

        self.service.client.chat.completions.create.side_effect = AuthenticationError(
            message="Invalid API key",
            response=mock_response,
            body=None
        )

        with pytest.raises(AIServiceError):
            await self.service.analyze_pdf_content("some pdf text", "test.pdf")


class TestTransportClassificationPrompt:
    """Test that the AI prompt correctly guides transport type classification."""

    def setup_method(self):
        self.service = AIService.__new__(AIService)
        self.service.ai_enabled = True
        self.service.client = MagicMock()

    async def _get_prompt_text(self):
        """Extract the prompt that would be sent to OpenAI by capturing the call args."""
        mock_response = MagicMock()
        mock_response.choices = [MagicMock()]
        mock_response.choices[0].message.content = json.dumps({
            "event_type": "ferry",
            "event_name": "Ferry MVD to BUE",
            "title": "Ferry MVD to BUE",
            "description": "Ferry ticket",
            "date": "2026-03-30",
            "time": "11:00",
            "venue_name": None,
            "venue_address": None,
            "city": "Montevideo",
            "state_country": "Uruguay",
            "organizer": None,
            "seat_info": None,
            "barcode_data": None,
            "barcode_numbers": None,
            "qr_text": None,
            "price": None,
            "confirmation_number": None,
            "gate_info": None,
            "latitude": None,
            "longitude": None,
            "additional_info": None,
            "confidence_score": 85,
            "multiple_events": "false",
            "performer_names": None,
            "exhibit_name": None,
            "has_assigned_seating": "false",
            "parking_info": None,
            "venue_type": "port",
            "nearby_landmarks": None,
            "public_transport": None,
            "accessibility": None,
            "passengers": None,
            "suggested_bg_color": "rgb(0, 102, 153)",
            "suggested_fg_color": "rgb(255, 255, 255)",
            "suggested_label_color": "rgb(200, 200, 200)"
        })
        self.service.client.chat.completions.create.return_value = mock_response

        await self.service._extract_pdf_metadata("Departure Port: Montevideo", "ferry.pdf")

        call_args = self.service.client.chat.completions.create.call_args
        # Extract prompt from call args (keyword or positional)
        if call_args.kwargs and "messages" in call_args.kwargs:
            messages = call_args.kwargs["messages"]
        else:
            messages = call_args.args[0] if call_args.args else []
        prompt = messages[1]["content"]
        return prompt

    @pytest.mark.asyncio
    async def test_prompt_contains_transport_type_guidance(self):
        prompt = await self._get_prompt_text()
        assert "TRANSPORT TYPE" in prompt

    @pytest.mark.asyncio
    async def test_prompt_mentions_ferry(self):
        prompt = await self._get_prompt_text()
        assert "ferry" in prompt.lower()

    @pytest.mark.asyncio
    async def test_prompt_mentions_ship_vessel(self):
        prompt = await self._get_prompt_text()
        lower = prompt.lower()
        assert "ship" in lower or "vessel" in lower

    @pytest.mark.asyncio
    async def test_prompt_warns_against_assuming_flight(self):
        prompt = await self._get_prompt_text()
        assert "Do NOT assume" in prompt and "flight" in prompt

    @pytest.mark.asyncio
    async def test_prompt_does_not_hardcode_company_names(self):
        prompt = await self._get_prompt_text()
        lower = prompt.lower()
        assert "buquebus" not in lower

    @pytest.mark.asyncio
    async def test_prompt_has_ferry_in_event_type_enum(self):
        prompt = await self._get_prompt_text()
        assert "ferry" in prompt

    @pytest.mark.asyncio
    async def test_prompt_has_bus_in_event_type_enum(self):
        prompt = await self._get_prompt_text()
        assert "bus" in prompt

    @pytest.mark.asyncio
    async def test_prompt_has_transport_direction(self):
        prompt = await self._get_prompt_text()
        assert "TRANSPORT DIRECTION" in prompt

    @pytest.mark.asyncio
    async def test_old_flight_direction_instruction_removed(self):
        prompt = await self._get_prompt_text()
        assert "FLIGHT DIRECTION" not in prompt
