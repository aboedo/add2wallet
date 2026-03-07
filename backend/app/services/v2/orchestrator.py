"""V2 orchestrator — ties the entire pipeline together.

Entry point: create_passes_v2()
Returns the same tuple as v1's create_pass_from_pdf_data for drop-in use:
    (pkpass_files, detected_barcodes, ticket_info, warnings)
"""

from __future__ import annotations

import json
import os
import tempfile
from typing import Any, Dict, List, Tuple

from app.services.v2.ai_extractor import ai_extractor
from app.services.v2.asset_generator import generate_assets
from app.services.v2.barcode_pipeline import extract_barcodes
from app.services.v2.color_extractor import extract_colors
from app.services.v2.models import ExtractedBarcode, PDFExtraction, PassJSON
from app.services.v2.pass_builder import build_pass
from app.services.v2.pass_signer import get_signer
from app.services.v2.pass_validator import validate_pass
from app.services.v2.pdf_analyzer import analyze_pdf


def create_passes_v2(
    pdf_bytes: bytes,
    filename: str,
) -> Tuple[List[bytes], List[Dict[str, Any]], List[Dict[str, Any]], List[str]]:
    """Process a PDF and produce Apple Wallet .pkpass files.

    Returns:
        pkpass_files      — list of .pkpass bytes (one per detected ticket)
        detected_barcodes — raw barcode dicts from the extractor
        ticket_info       — list of dicts describing each generated ticket
        warnings          — human-readable warning strings
    """
    print(f"🔍 [v2] Processing: {filename}")
    all_warnings: List[str] = []

    # ------------------------------------------------------------------
    # Step 1: Extract PDF text
    # ------------------------------------------------------------------
    analysis = analyze_pdf(pdf_bytes, filename)
    print(f"📝 [v2] PDF: {analysis.page_count} page(s), {len(analysis.text)} chars")

    # ------------------------------------------------------------------
    # Step 2: Extract barcodes
    # ------------------------------------------------------------------
    barcodes, bc_warnings = extract_barcodes(pdf_bytes, filename)
    all_warnings.extend(bc_warnings)

    # Build raw barcode dicts for the API response (backwards compat)
    detected_barcodes_raw: List[Dict[str, Any]] = [
        {
            "data": bc.message,
            "type": bc.source_type,
            "format": bc.pk_format,
            "confidence": bc.confidence,
        }
        for bc in barcodes
    ]

    # ------------------------------------------------------------------
    # Step 3: AI extraction (single call)
    # ------------------------------------------------------------------
    extraction: PDFExtraction = ai_extractor.extract(analysis.text_for_ai, filename)

    # ------------------------------------------------------------------
    # Step 4: Extract colors
    # ------------------------------------------------------------------
    bg_color, fg_color, label_color = extract_colors(pdf_bytes, extraction.document_type)

    # ------------------------------------------------------------------
    # Step 5: Consolidate barcodes and determine ticket count
    # ------------------------------------------------------------------
    barcodes = _consolidate_barcodes(barcodes, extraction)
    total_tickets = max(1, len(barcodes))
    print(f"🎫 [v2] {total_tickets} ticket(s) after consolidation")
    signer = get_signer()
    pass_type_id, team_id = signer.get_identifiers()

    pkpass_files: List[bytes] = []
    ticket_info: List[Dict[str, Any]] = []

    for i in range(total_tickets):
        # Select the barcode for this ticket slot (empty list → barcode-less pass)
        ticket_barcodes = [barcodes[i]] if i < len(barcodes) else []

        # Build PassJSON
        pass_json = build_pass(
            extraction=extraction,
            barcodes=ticket_barcodes,
            bg_color=bg_color,
            fg_color=fg_color,
            label_color=label_color,
            ticket_index=i,
            total_tickets=total_tickets,
            pass_type_id=pass_type_id,
            team_id=team_id,
        )

        # Validate before signing
        is_valid, validation_errors = validate_pass(pass_json)
        if not is_valid:
            print(f"⚠️ [v2] Validation issues for ticket {i + 1}: {validation_errors}")
            for err in validation_errors:
                msg = f"Validation: {err}"
                if msg not in all_warnings:
                    all_warnings.append(msg)
        else:
            print(f"✅ [v2] Pass validation passed for ticket {i + 1}")

        # Sign and package
        pkpass_data = _package_pass(pass_json, pdf_bytes, extraction, bg_color, fg_color)
        pkpass_files.append(pkpass_data)

        # Build ticket_info entry for backwards-compat API response
        barcode_entry: Dict[str, Any] | None = None
        if ticket_barcodes:
            bc = ticket_barcodes[0]
            barcode_entry = {
                "data": bc.message,
                "type": bc.source_type,
                "format": bc.pk_format,
            }

        # Reconstruct title with optional numbering
        title = extraction.title
        if total_tickets > 1:
            title = f"{extraction.title} (#{i + 1})"

        ticket_info.append({
            "ticket_number": i + 1,
            "total_tickets": total_tickets,
            "title": title,
            "description": pass_json.description,
            "barcode": barcode_entry,
            "metadata": {
                "title": extraction.title,
                "event_name": extraction.event_name,
                "venue_name": extraction.venue_name,
                "date": extraction.date,
                "time": extraction.time,
                "seat_info": extraction.seat_info,
                "gate_info": extraction.gate_info,
                "confirmation_number": extraction.confirmation_number,
                "performer": extraction.performer,
                "price": extraction.price,
                "organization": extraction.organization,
                "event_type": extraction.document_type,
                "background_color": bg_color,
                "foreground_color": fg_color,
                "label_color": label_color,
                "ai_processed": ai_extractor.enabled,
                "confidence_score": extraction.confidence,
            },
        })

    print(f"✅ [v2] Generated {len(pkpass_files)} pass(es)")
    return pkpass_files, detected_barcodes_raw, ticket_info, all_warnings


# ---------------------------------------------------------------------------
# Barcode consolidation
# ---------------------------------------------------------------------------

# Priority: higher = better primary barcode
_FORMAT_PRIORITY = {
    "PDF417": 5,
    "AZTEC": 4,
    "QRCODE": 3,
    "CODE128": 2,
    "CODE39": 2,
    "DATA MATRIX": 1,
    "DATAMATRIX": 1,
    "EAN13": 1,
    "EAN8": 1,
}


def _consolidate_barcodes(
    barcodes: List["ExtractedBarcode"],
    extraction: "PDFExtraction",
) -> List["ExtractedBarcode"]:
    """Reduce barcodes to the minimum set needed.

    - If AI says multiple_tickets=True → keep all (one pass per barcode)
    - Otherwise → pick the single best primary barcode:
        * Skip URL barcodes (message starts with http/https) — they're redirect links
        * Prefer by format priority (PDF417 > Aztec > QR > 1D > DataMatrix)
        * Break ties by payload length (longer = more info)
    """
    if not barcodes:
        return barcodes

    if len(barcodes) == 1:
        return barcodes

    # Always filter out URL-only barcodes (redirect links, not scan codes)
    real_barcodes = [
        bc for bc in barcodes
        if not bc.message.startswith(("http://", "https://"))
    ]
    if not real_barcodes:
        real_barcodes = barcodes  # all are URLs — keep first one as fallback

    if extraction.multiple_tickets and len(real_barcodes) >= 3:
        print(f"🎫 [v2] multiple_tickets=True — keeping all {len(real_barcodes)} barcodes")
        return real_barcodes

    # Pick primary by priority then payload length
    def _score(bc: "ExtractedBarcode") -> tuple:
        prio = _FORMAT_PRIORITY.get(bc.source_type.upper(), 0)
        return (prio, len(bc.message))

    primary = max(real_barcodes, key=_score)
    print(
        f"🎫 [v2] Consolidated {len(barcodes)} barcodes → 1 "
        f"(primary: {primary.source_type}, {len(primary.message)} chars)"
    )
    return [primary]


# ---------------------------------------------------------------------------
# Internal packaging helper
# ---------------------------------------------------------------------------

def _package_pass(
    pass_json: PassJSON,
    pdf_bytes: bytes,
    extraction: PDFExtraction,
    bg_color: str,
    fg_color: str,
) -> bytes:
    signer = get_signer()

    with tempfile.TemporaryDirectory() as tmp:
        # Serialize PassJSON to dict, converting nested Pydantic models to plain dicts
        pass_data = _serialize(pass_json.model_dump(exclude_none=True))

        with open(os.path.join(tmp, "pass.json"), "w", encoding="utf-8") as f:
            json.dump(pass_data, f, indent=2, ensure_ascii=False)

        # Generate icon / thumbnail assets
        generate_assets(
            pass_dir=tmp,
            pdf_bytes=pdf_bytes,
            document_type=extraction.document_type,
            title=extraction.title,
            bg_color=bg_color,
            fg_color=fg_color,
        )

        return signer.package_pass(tmp)


def _serialize(obj: Any) -> Any:
    """Recursively convert Pydantic models and bytes to JSON-safe types."""
    if hasattr(obj, "model_dump"):
        return _serialize(obj.model_dump(exclude_none=True))
    if isinstance(obj, dict):
        return {k: _serialize(v) for k, v in obj.items() if v is not None}
    if isinstance(obj, list):
        return [_serialize(item) for item in obj]
    if isinstance(obj, bytes):
        return obj.decode("latin-1")  # preserve byte values
    return obj
