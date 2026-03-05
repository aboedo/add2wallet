"""Eval suite — Ignacio feedback PDFs with real AI pipeline.

Run manually only (requires OPENAI_API_KEY):
    pytest tests/eval/test_ignacio_eval.py -v

Each test spec documents:
  - expected_passes   : how many .pkpass files
  - expected_title    : substring expected in ticket title (case-insensitive)
  - expected_date     : expected date string (YYYY-MM-DD)
  - expected_barcode  : expected PKBarcodeFormat value
  - notes             : Ignacio's original feedback

Results are also written to tests/eval/results/YYYY-MM-DD_HH-MM.json for trend tracking.
"""

import asyncio
import io
import json
import os
import zipfile
from datetime import datetime
from typing import Any, Dict, List, Optional

import pytest

# ---------------------------------------------------------------------------
# Skip entire module unless OPENAI_API_KEY is set
# (guard must be before app imports so missing deps don't break collection)
# ---------------------------------------------------------------------------

if not os.getenv("OPENAI_API_KEY"):
    pytest.skip(
        "OPENAI_API_KEY not set — eval suite requires real AI. "
        "Run with: OPENAI_API_KEY=... pytest tests/eval/test_ignacio_eval.py -v",
        allow_module_level=True,
    )

try:
    from app.services.ai_service import ai_service
    from app.services.barcode_extractor import BarcodeExtractor
    from app.services.pass_generator import PassGenerator
except Exception as e:  # noqa: BLE001
    pytest.skip(f"App imports failed: {e}", allow_module_level=True)

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

IGNACIO_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__)
    )))),
    "test-files",
    "ignacio-feedback",
)

RESULTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results")
os.makedirs(RESULTS_DIR, exist_ok=True)

# ---------------------------------------------------------------------------
# Eval spec — one entry per PDF
# ---------------------------------------------------------------------------

EVAL_SPECS = [
    {
        "file": "1-Notre-Dame.pdf",
        "expected_passes": 4,
        "expected_title": "notre",           # "Notre-Dame de Paris"
        "expected_date": "2025-06-07",
        "expected_barcode": "PKBarcodeFormatQR",
        "notes": "perfect; recognized 4 tickets",
    },
    {
        "file": "2-AbuDhabi-Madrid.pdf",
        "expected_passes": 1,
        "expected_title": None,              # Etihad / flight generic OK
        "expected_date": None,               # date was missing — still TBD
        "expected_barcode": "PKBarcodeFormatPDF417",
        "notes": "generated but sparse data",
    },
    {
        "file": "3-Malaga-Madrid.pdf",
        "expected_passes": 1,
        "expected_title": "malaga",
        "expected_date": "2024-06-22",
        "expected_barcode": None,            # any barcode OK
        "notes": "was HTTP 400 — must not error",
    },
    {
        "file": "4-Benfica.pdf",
        "expected_passes": 1,
        "expected_title": "benfica",
        "expected_date": None,
        "expected_barcode": None,
        "notes": "was 'data couldn't be read'",
    },
    {
        "file": "5-Monasterio-Lisboa.pdf",
        "expected_passes": 1,
        "expected_title": "jer",             # Jerónimos
        "expected_date": "2025-02-08",
        "expected_barcode": "PKBarcodeFormatQR",
        "notes": "perfect (minor formatting)",
    },
    {
        "file": "6-Cine-Gladiador.pdf",
        "expected_passes": 1,
        "expected_title": "gladiator",
        "expected_date": "2025-01-11",
        "expected_barcode": "PKBarcodeFormatQR",
        "notes": "worked well; seat numbers hard",
    },
    {
        "file": "7-Madrid-Medellin.pdf",
        "expected_passes": 1,
        "expected_title": "madrid",          # origin must be Madrid
        "expected_date": "2022-08-23",
        "expected_barcode": "PKBarcodeFormatPDF417",
        "notes": "was reversed + 3 passes; origin=Madrid, dest=Medellín",
        "extra_checks": ["origin_is_madrid"],
    },
    {
        "file": "8-Reina-Sofia.pdf",
        "expected_passes": 1,
        "expected_title": "reina",
        "expected_date": "2024-03-17",
        "expected_barcode": None,
        "notes": "perfect — regression guard",
    },
    {
        "file": "9-JO-Paris.pdf",
        "expected_passes": 2,
        "expected_title": None,
        "expected_date": "2024-08-09",
        "expected_barcode": "PKBarcodeFormatQR",
        "notes": "503 initially; worked after retries",
    },
    {
        "file": "10-Catedral-Malaga.pdf",
        "expected_passes": 1,
        "expected_title": "catedral",
        "expected_date": "2024-01-20",
        "expected_barcode": None,
        "notes": "surprisingly good",
    },
    {
        "file": "11-Orsay.pdf",
        "expected_passes": 1,
        "expected_title": "orsay",
        "expected_date": None,               # date not on ticket — acceptable
        "expected_barcode": None,
        "notes": "date not recognized; 2 barcodes but 1 ticket",
    },
    {
        "file": "12-Penarol.pdf",
        "expected_passes": 1,
        "expected_title": "peñarol",
        "expected_date": "2023-12-09",
        "expected_barcode": "PKBarcodeFormatPDF417",
        "notes": "never worked; now fixed via zxing-cpp",
    },
    {
        "file": "13-Oppenheimer.pdf",
        "expected_passes": 1,
        "expected_title": "oppenheimer",
        "expected_date": "2023-07-30",
        "expected_barcode": "PKBarcodeFormatQR",
        "notes": "worked",
    },
]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _load(filename: str) -> bytes:
    path = os.path.join(IGNACIO_DIR, filename)
    if not os.path.exists(path):
        pytest.skip(f"{filename} not found at {path}")
    with open(path, "rb") as f:
        return f.read()


def _pass_json(pkpass_bytes: bytes) -> dict:
    with zipfile.ZipFile(io.BytesIO(pkpass_bytes)) as z:
        return json.loads(z.read("pass.json"))


def _barcode_format(pkpass_bytes: bytes) -> Optional[str]:
    pj = _pass_json(pkpass_bytes)
    barcodes = pj.get("barcodes") or ([pj["barcode"]] if pj.get("barcode") else [])
    return barcodes[0].get("format") if barcodes else None


def _run_pipeline(filename: str):
    """Run full pipeline with real AI. Returns (pkpass_files, barcodes, ticket_info, warnings)."""
    pdf_data = _load(filename)
    pg = PassGenerator()

    # Extract text then call AI (same as main.py does)
    pdf_text = pg._extract_pdf_text(pdf_data)
    ai_metadata = asyncio.get_event_loop().run_until_complete(
        ai_service.analyze_pdf_content(pdf_text, filename)
    )

    return pg.create_pass_from_pdf_data(pdf_data, filename, ai_metadata), ai_metadata


# ---------------------------------------------------------------------------
# Result collector — writes JSON report at end of session
# ---------------------------------------------------------------------------

_eval_results: List[Dict[str, Any]] = []


def _record(spec: dict, passed: bool, actual: dict, failure: str = ""):
    _eval_results.append({
        "file": spec["file"],
        "passed": passed,
        "expected_passes": spec["expected_passes"],
        "actual_passes": actual.get("passes"),
        "expected_title": spec["expected_title"],
        "actual_title": actual.get("title"),
        "expected_date": spec["expected_date"],
        "actual_date": actual.get("date"),
        "expected_barcode": spec["expected_barcode"],
        "actual_barcode": actual.get("barcode"),
        "failure": failure,
        "notes": spec["notes"],
    })


def pytest_sessionfinish(session, exitstatus):
    if not _eval_results:
        return
    ts = datetime.now().strftime("%Y-%m-%d_%H-%M")
    out = os.path.join(RESULTS_DIR, f"{ts}.json")
    with open(out, "w") as f:
        json.dump(_eval_results, f, indent=2)
    total = len(_eval_results)
    passed = sum(1 for r in _eval_results if r["passed"])
    print(f"\n📊 Eval results: {passed}/{total} passed → {out}")


# ---------------------------------------------------------------------------
# Parametrized test
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("spec", EVAL_SPECS, ids=[s["file"] for s in EVAL_SPECS])
def test_pdf_eval(spec):
    filename = spec["file"]
    failures = []
    actual = {}

    (pkpass_files, barcodes, ticket_info, warnings), ai_metadata = _run_pipeline(filename)

    # — pass count —
    actual["passes"] = len(pkpass_files)
    if len(pkpass_files) != spec["expected_passes"]:
        failures.append(
            f"passes: expected {spec['expected_passes']}, got {len(pkpass_files)}"
        )

    # — title —
    actual["title"] = ticket_info[0].get("title", "") if ticket_info else ""
    if spec["expected_title"] and ticket_info:
        title_lower = actual["title"].lower()
        if spec["expected_title"].lower() not in title_lower:
            failures.append(
                f"title: '{spec['expected_title']}' not in '{actual['title']}'"
            )

    # — date —
    actual["date"] = ticket_info[0].get("date", "") if ticket_info else ""
    if spec["expected_date"] and ticket_info:
        if spec["expected_date"] not in str(actual["date"]):
            failures.append(
                f"date: expected '{spec['expected_date']}', got '{actual['date']}'"
            )

    # — barcode format —
    actual["barcode"] = _barcode_format(pkpass_files[0]) if pkpass_files else None
    if spec["expected_barcode"] and pkpass_files:
        if actual["barcode"] != spec["expected_barcode"]:
            failures.append(
                f"barcode: expected {spec['expected_barcode']}, got {actual['barcode']}"
            )

    # — extra checks —
    for check in spec.get("extra_checks", []):
        if check == "origin_is_madrid":
            desc = json.dumps(
                {k: v for k, v in (ticket_info[0] if ticket_info else {}).items()
                 if not isinstance(v, bytes)},
                ensure_ascii=False
            ).lower()
            if "madrid" not in desc:
                failures.append("origin_is_madrid: 'madrid' not found in ticket_info")

    passed = len(failures) == 0
    _record(spec, passed, actual, "; ".join(failures))

    if failures:
        pytest.fail(
            f"\n{filename} ({spec['notes']})\n" +
            "\n".join(f"  ✗ {f}" for f in failures)
        )
