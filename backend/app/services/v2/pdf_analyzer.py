"""PDF text and metadata extraction — no AI, no barcode scanning."""

from __future__ import annotations

import io
from dataclasses import dataclass, field
from typing import List, Optional


@dataclass
class PDFAnalysis:
    """Results from analyzing a PDF document."""
    text: str
    page_count: int
    filename: str
    # Truncated text safe to send to AI (first 4000 chars)
    text_for_ai: str = field(init=False)

    def __post_init__(self) -> None:
        self.text_for_ai = self.text[:4000].strip()


def analyze_pdf(pdf_bytes: bytes, filename: str) -> PDFAnalysis:
    """Extract text from a PDF and return a PDFAnalysis object.

    Tries PyMuPDF first (faster, better for PDFs with embedded fonts),
    falls back to PyPDF2 if unavailable.
    """
    text = _extract_with_fitz(pdf_bytes) or _extract_with_pypdf2(pdf_bytes)
    page_count = _count_pages(pdf_bytes)
    return PDFAnalysis(text=text, page_count=page_count, filename=filename)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _extract_with_fitz(pdf_bytes: bytes) -> Optional[str]:
    try:
        import fitz  # type: ignore

        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
        parts: List[str] = []
        for page in doc:
            parts.append(page.get_text())
        doc.close()
        result = "\n".join(parts).strip()
        if result:
            print(f"📝 PyMuPDF extracted {len(result)} chars of PDF text")
        return result or None
    except Exception as exc:
        print(f"⚠️ PyMuPDF text extraction failed: {exc}")
        return None


def _extract_with_pypdf2(pdf_bytes: bytes) -> str:
    try:
        import PyPDF2  # type: ignore

        reader = PyPDF2.PdfReader(io.BytesIO(pdf_bytes))
        parts: List[str] = []
        for page in reader.pages:
            parts.append(page.extract_text() or "")
        result = "\n".join(parts).strip()
        print(f"📝 PyPDF2 extracted {len(result)} chars of PDF text")
        return result
    except Exception as exc:
        print(f"⚠️ PyPDF2 text extraction failed: {exc}")
        return ""


def _count_pages(pdf_bytes: bytes) -> int:
    try:
        import fitz  # type: ignore

        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
        count = doc.page_count
        doc.close()
        return count
    except Exception:
        pass
    try:
        import PyPDF2  # type: ignore

        return len(PyPDF2.PdfReader(io.BytesIO(pdf_bytes)).pages)
    except Exception:
        return 1
