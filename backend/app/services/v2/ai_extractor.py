"""Single focused LLM call with structured output for PDF metadata extraction.

Uses OpenAI's structured output (response_format json_schema / parse API)
to return a validated PDFExtraction model.  Never asks the model to search
the web or invent data — only what is explicitly present in the document.
"""

from __future__ import annotations

import json
import os
from typing import Optional

from app.services.v2.models import PDFExtraction

_EXTRACTION_PROMPT = """\
You are extracting information from a ticket or pass document to populate an Apple Wallet pass.

RULES:
- Return ONLY information that is explicitly present in the document text.
- Do NOT infer, guess, or search for information not in the text.
- If a field is not present, leave it null.
- For the title: max 30 characters, use the most prominent proper noun (event name, venue name, show title, etc.)
- For date: ISO 8601 format YYYY-MM-DD
- For time: HH:MM (24-hour)
- document_type must be one of: event_ticket, boarding_pass, transit, hotel, generic

DOCUMENT FILENAME: {filename}

DOCUMENT TEXT:
{text}
"""

_JSON_SCHEMA = {
    "type": "object",
    "properties": {
        "document_type": {
            "type": "string",
            "enum": ["event_ticket", "boarding_pass", "transit", "hotel", "generic"],
        },
        "title": {"type": "string"},
        "organization": {"type": ["string", "null"]},
        "event_name": {"type": ["string", "null"]},
        "venue_name": {"type": ["string", "null"]},
        "venue_address": {"type": ["string", "null"]},
        "date": {"type": ["string", "null"]},
        "time": {"type": ["string", "null"]},
        "seat_info": {"type": ["string", "null"]},
        "gate_info": {"type": ["string", "null"]},
        "confirmation_number": {"type": ["string", "null"]},
        "performer": {"type": ["string", "null"]},
        "price": {"type": ["string", "null"]},
        "confidence": {"type": "integer", "minimum": 0, "maximum": 100},
    },
    "required": ["document_type", "title", "confidence"],
    "additionalProperties": False,
}


class AIExtractor:
    def __init__(self, api_key: Optional[str] = None) -> None:
        self.api_key = api_key or os.getenv("OPENAI_API_KEY")
        self.enabled = bool(self.api_key)
        self._client = None

        if self.enabled:
            try:
                from openai import OpenAI
                self._client = OpenAI(api_key=self.api_key, timeout=30.0)
                print("🤖 AI extractor v2 initialised")
            except Exception as exc:
                print(f"❌ Failed to init OpenAI client: {exc}")
                self.enabled = False

    def extract(self, text: str, filename: str) -> PDFExtraction:
        """Run the single LLM extraction call and return a PDFExtraction.

        Falls back to heuristic extraction if AI is disabled or fails.
        """
        if not self.enabled or not self._client:
            print("🔄 AI disabled — using heuristic extraction")
            return _heuristic_extract(text, filename)

        try:
            return self._call_openai(text, filename)
        except Exception as exc:
            print(f"⚠️ AI extraction failed ({exc}) — using heuristic fallback")
            return _heuristic_extract(text, filename)

    def _call_openai(self, text: str, filename: str) -> PDFExtraction:
        model = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
        prompt = _EXTRACTION_PROMPT.format(
            filename=filename,
            text=text[:4000],
        )

        # Prefer structured output (OpenAI SDK >= 1.40)
        try:
            resp = self._client.beta.chat.completions.parse(  # type: ignore[attr-defined]
                model=model,
                messages=[
                    {
                        "role": "system",
                        "content": (
                            "You extract structured information from ticket and pass documents. "
                            "Only return information explicitly present in the text."
                        ),
                    },
                    {"role": "user", "content": prompt},
                ],
                response_format=PDFExtraction,
                temperature=0.0,
                max_tokens=600,
            )
            result: PDFExtraction = resp.choices[0].message.parsed  # type: ignore[union-attr]
            print(
                f"✅ AI extraction complete: type={result.document_type}, "
                f"title='{result.title}', confidence={result.confidence}"
            )
            return result
        except Exception:
            pass

        # Fallback: manual JSON schema
        resp = self._client.chat.completions.create(
            model=model,
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You extract structured information from ticket and pass documents. "
                        "Only return information explicitly present in the text. "
                        "Return valid JSON matching the provided schema exactly."
                    ),
                },
                {"role": "user", "content": prompt},
            ],
            response_format={
                "type": "json_schema",
                "json_schema": {
                    "name": "pdf_extraction",
                    "schema": _JSON_SCHEMA,
                    "strict": True,
                },
            },
            temperature=0.0,
            max_tokens=600,
        )
        raw = resp.choices[0].message.content or "{}"
        data = json.loads(raw)
        result = PDFExtraction(**data)
        print(
            f"✅ AI extraction complete (json_schema): type={result.document_type}, "
            f"title='{result.title}', confidence={result.confidence}"
        )
        return result


# ---------------------------------------------------------------------------
# Heuristic fallback
# ---------------------------------------------------------------------------

def _heuristic_extract(text: str, filename: str) -> PDFExtraction:
    """Very basic regex-based extraction when AI is unavailable."""
    import re

    t = text.lower()

    # Document type
    if any(w in t for w in ["boarding", "airline", "flight", "gate"]):
        doc_type = "boarding_pass"
    elif any(w in t for w in ["train", "rail", "platform"]):
        doc_type = "transit"
    elif any(w in t for w in ["hotel", "check-in", "checkout", "reservation"]):
        doc_type = "hotel"
    elif any(w in t for w in ["ticket", "concert", "event", "show", "festival", "museum", "admission"]):
        doc_type = "event_ticket"
    else:
        doc_type = "generic"

    # Title from filename
    base = filename.replace(".pdf", "").replace("_", " ").strip()
    base = re.sub(r"\s+", " ", base)
    if len(re.sub(r"[^A-Za-z]", "", base)) < 3:
        title = "Digital Ticket"
    else:
        title = base[:30]

    # Date
    date_m = re.search(r"\b(\d{4}-\d{2}-\d{2})\b", text)
    date_val: Optional[str] = date_m.group(1) if date_m else None

    # Time
    time_m = re.search(r"\b(\d{1,2}:\d{2})\b", text)
    time_val: Optional[str] = time_m.group(1) if time_m else None

    return PDFExtraction(
        document_type=doc_type,  # type: ignore[arg-type]
        title=title,
        date=date_val,
        time=time_val,
        confidence=25,
    )


# Global instance
ai_extractor = AIExtractor()
