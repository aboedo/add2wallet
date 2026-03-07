"""Head-to-head comparison of v1 and v2 pipelines against all test PDFs.

Usage:
    cd backend
    OPENAI_API_KEY=sk-... python3 tests/eval/compare_v1_v2.py

Outputs a side-by-side table and saves JSON to tests/eval/results/compare_YYYY-MM-DD_HH-MM.json
"""

from __future__ import annotations

import asyncio
import io
import json
import os
import sys
import time
import zipfile
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

IGNACIO_DIR = Path(__file__).parent.parent.parent.parent / "test-files" / "ignacio-feedback"
RESULTS_DIR = Path(__file__).parent / "results"
RESULTS_DIR.mkdir(parents=True, exist_ok=True)

PDFS = sorted(IGNACIO_DIR.glob("*.pdf"))

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _pass_json(pkpass_bytes: bytes) -> dict:
    with zipfile.ZipFile(io.BytesIO(pkpass_bytes)) as z:
        return json.loads(z.read("pass.json"))


def _barcode_format(pkpass_bytes: bytes) -> Optional[str]:
    pj = _pass_json(pkpass_bytes)
    barcodes = pj.get("barcodes") or ([pj["barcode"]] if pj.get("barcode") else [])
    return barcodes[0].get("format") if barcodes else None


def _run_v1(pdf_bytes: bytes, filename: str, ai_metadata) -> Tuple[dict, float]:
    from app.services.pass_generator import PassGenerator
    pg = PassGenerator()
    t0 = time.time()
    pkpass_files, barcodes, ticket_info, warnings = pg.create_pass_from_pdf_data(
        pdf_bytes, filename, ai_metadata
    )
    elapsed = time.time() - t0

    result = {
        "passes": len(pkpass_files),
        "barcodes": [{"type": b.get("type"), "format": b.get("format")} for b in barcodes],
        "title": ticket_info[0].get("title", "") if ticket_info else "",
        "date": ticket_info[0].get("date", "") or ticket_info[0].get("metadata", {}).get("date", "") if ticket_info else "",
        "barcode_format": _barcode_format(pkpass_files[0]) if pkpass_files else None,
        "warnings": warnings,
        "error": None,
        "elapsed_s": round(elapsed, 2),
    }
    return result


def _run_v2(pdf_bytes: bytes, filename: str) -> Tuple[dict, float]:
    from app.services.v2.orchestrator import create_passes_v2
    t0 = time.time()
    pkpass_files, barcodes, ticket_info, warnings = create_passes_v2(pdf_bytes, filename)
    elapsed = time.time() - t0

    result = {
        "passes": len(pkpass_files),
        "barcodes": [{"type": b.get("type"), "format": b.get("format")} for b in barcodes],
        "title": ticket_info[0].get("title", "") if ticket_info else "",
        "date": ticket_info[0].get("metadata", {}).get("date", "") if ticket_info else "",
        "barcode_format": _barcode_format(pkpass_files[0]) if pkpass_files else None,
        "warnings": warnings,
        "error": None,
        "elapsed_s": round(elapsed, 2),
    }
    return result


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        print("❌ OPENAI_API_KEY not set")
        sys.exit(1)

    from app.services.ai_service import ai_service
    from app.services.pass_generator import PassGenerator

    results = []
    pg = PassGenerator()

    col_w = 30
    header = f"{'PDF':<28} {'V1 passes':>9} {'V2 passes':>9} {'V1 title':<28} {'V2 title':<28} {'V1 bc':<24} {'V2 bc':<24} {'V1 date':<12} {'V2 date':<12} {'V1 t':>6} {'V2 t':>6}"
    print("\n" + "="*len(header))
    print(header)
    print("="*len(header))

    for pdf_path in PDFS:
        filename = pdf_path.name
        pdf_bytes = pdf_path.read_bytes()

        # Shared AI extraction (same as prod — both v1 and v2 benefit from it)
        pdf_text = pg._extract_pdf_text(pdf_bytes)
        ai_metadata = asyncio.get_event_loop().run_until_complete(
            ai_service.analyze_pdf_content(pdf_text, filename)
        )

        # --- V1 ---
        v1 = {"passes": "ERR", "title": "", "date": "", "barcode_format": None, "elapsed_s": 0, "error": None, "warnings": []}
        try:
            v1 = _run_v1(pdf_bytes, filename, ai_metadata)
        except Exception as e:
            v1["error"] = str(e)[:80]

        # --- V2 ---
        v2 = {"passes": "ERR", "title": "", "date": "", "barcode_format": None, "elapsed_s": 0, "error": None, "warnings": []}
        try:
            v2 = _run_v2(pdf_bytes, filename)
        except Exception as e:
            v2["error"] = str(e)[:80]

        # Print row
        name = filename[:26]
        v1p = str(v1["passes"])
        v2p = str(v2["passes"])
        v1t = (v1["title"] or "")[:26]
        v2t = (v2["title"] or "")[:26]
        v1bc = (v1["barcode_format"] or v1.get("error") or "")[:22]
        v2bc = (v2["barcode_format"] or v2.get("error") or "")[:22]
        v1d = str(v1["date"] or "")[:10]
        v2d = str(v2["date"] or "")[:10]
        v1s = f"{v1['elapsed_s']}s"
        v2s = f"{v2['elapsed_s']}s"

        row = f"{name:<28} {v1p:>9} {v2p:>9} {v1t:<28} {v2t:<28} {v1bc:<24} {v2bc:<24} {v1d:<12} {v2d:<12} {v1s:>6} {v2s:>6}"
        print(row)

        results.append({
            "file": filename,
            "v1": v1,
            "v2": v2,
        })

    print("=" * len(header) + "\n")

    # Summary
    v1_ok = sum(1 for r in results if not r["v1"].get("error") and r["v1"]["passes"] >= 1)
    v2_ok = sum(1 for r in results if not r["v2"].get("error") and r["v2"]["passes"] >= 1)
    v1_single = sum(1 for r in results if r["v1"]["passes"] == 1)
    v2_single = sum(1 for r in results if r["v2"]["passes"] == 1)
    print(f"V1: {v1_ok}/{len(results)} generated at least 1 pass, {v1_single}/{len(results)} generated exactly 1")
    print(f"V2: {v2_ok}/{len(results)} generated at least 1 pass, {v2_single}/{len(results)} generated exactly 1")

    # Save
    ts = datetime.now().strftime("%Y-%m-%d_%H-%M")
    out = RESULTS_DIR / f"compare_{ts}.json"
    out.write_text(json.dumps(results, indent=2, default=str))
    print(f"\n📊 Full results → {out}")


if __name__ == "__main__":
    main()
