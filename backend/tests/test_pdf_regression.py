"""Regression suite over every checked-in sample document.

These assert *structural* invariants rather than extracted wording, so they do
not go flaky when the model phrases a title differently. Every invariant here
corresponds to a bug that actually shipped:

  - a dict reached a pass field and rendered as "{'car': 1, 'seats': [9, 10]}"
  - a Data Matrix / Code128 was emitted as PKBarcodeFormatQR
  - a multi-day booking expired before it ended
  - legs of one itinerary all carried the same page's data

They run without an API key: the pipeline falls back to regex extraction and
still builds real, signed passes, which is exactly the layer under test.
"""

from __future__ import annotations

import asyncio
import io
import json
import os
import zipfile
from pathlib import Path

import pytest

from app.core.config import get_settings
from app.core.pipeline import ConversionPipeline
from app.core.pkpass_validation import validate_pkpass
from app.core.storage import JobStore


BACKEND_DIR = Path(__file__).resolve().parent.parent
SAMPLE_DIRS = [
    BACKEND_DIR / "test_files",
    BACKEND_DIR / "tests" / "fixtures",
    BACKEND_DIR.parent / "test-files" / "ignacio-feedback",
]

VALID_PK_FORMATS = {
    "PKBarcodeFormatQR",
    "PKBarcodeFormatPDF417",
    "PKBarcodeFormatAztec",
    "PKBarcodeFormatCode128",
}

REQUIRED_PASS_KEYS = {
    "formatVersion",
    "passTypeIdentifier",
    "serialNumber",
    "teamIdentifier",
    "organizationName",
    "description",
}

STYLE_KEYS = ("eventTicket", "generic", "boardingPass", "coupon", "storeCard")


def _samples() -> list[Path]:
    files: list[Path] = []
    for directory in SAMPLE_DIRS:
        if directory.is_dir():
            files.extend(sorted(p for p in directory.glob("*.pdf")))
    return files


SAMPLES = _samples()


@pytest.fixture(scope="module")
def converted() -> dict[str, dict]:
    """Run every sample through the real pipeline once and cache the result."""
    settings = get_settings()
    store = JobStore(settings)
    pipeline = ConversionPipeline(settings, store)

    results: dict[str, dict] = {}
    for path in SAMPLES:
        job = asyncio.run(
            pipeline.convert(
                filename=path.name,
                content_type="application/pdf",
                data=path.read_bytes(),
                user_id="regression",
                session_token="regression",
                is_retry=False,
                is_demo=True,
            )
        )
        results[path.name] = {
            "passes": [_read_pass(p.read_bytes()) for p in job.pass_paths],
            "raw": [p.read_bytes() for p in job.pass_paths],
            "ticket_info": job.ticket_info,
            "metadata": job.ai_metadata or {},
        }
    return results


def _read_pass(data: bytes) -> dict:
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        return json.loads(archive.read("pass.json"))


def _all_fields(pass_json: dict) -> list[dict]:
    structure = next((pass_json[key] for key in STYLE_KEYS if key in pass_json), {})
    fields: list[dict] = []
    for section in ("headerFields", "primaryFields", "secondaryFields", "auxiliaryFields", "backFields"):
        fields.extend(structure.get(section) or [])
    return fields


pytestmark = pytest.mark.skipif(not SAMPLES, reason="No sample documents checked in")


@pytest.mark.parametrize("name", [p.name for p in SAMPLES])
def test_every_sample_produces_at_least_one_pass(converted, name):
    assert converted[name]["passes"], f"{name} produced no pass"


@pytest.mark.parametrize("name", [p.name for p in SAMPLES])
def test_passes_have_the_keys_apple_requires(converted, name):
    for pass_json in converted[name]["passes"]:
        missing = REQUIRED_PASS_KEYS - set(pass_json)
        assert not missing, f"{name}: pass.json missing {sorted(missing)}"
        assert any(key in pass_json for key in STYLE_KEYS), f"{name}: no pass style block"


@pytest.mark.parametrize("name", [p.name for p in SAMPLES])
def test_no_field_leaks_a_python_repr(converted, name):
    """seat_info arrived as a dict and rendered as "{'car': 1, 'seats': [9, 10]}"."""
    for pass_json in converted[name]["passes"]:
        for field in _all_fields(pass_json):
            value = str(field.get("value", ""))
            assert not value.startswith(("{", "[")), f"{name}: raw structure in {field.get('key')}: {value}"
            assert "': " not in value, f"{name}: dict repr in {field.get('key')}: {value}"
            assert value.strip(), f"{name}: empty value for {field.get('key')}"


@pytest.mark.parametrize("name", [p.name for p in SAMPLES])
def test_barcodes_declare_a_real_wallet_format(converted, name):
    """A mislabelled format produced an unscannable code that Wallet still showed."""
    for pass_json in converted[name]["passes"]:
        for barcode in pass_json.get("barcodes") or []:
            assert barcode["format"] in VALID_PK_FORMATS, f"{name}: bad format {barcode['format']}"
            assert barcode.get("message"), f"{name}: barcode with no message"
            assert barcode.get("messageEncoding"), f"{name}: barcode with no encoding"


TYPE_TO_PK_FORMAT = {
    "QRCODE": "PKBarcodeFormatQR",
    "PDF417": "PKBarcodeFormatPDF417",
    "AZTEC": "PKBarcodeFormatAztec",
    "CODE128": "PKBarcodeFormatCode128",
    "CODE39": "PKBarcodeFormatCode128",
    "CODE93": "PKBarcodeFormatCode128",
    "EAN13": "PKBarcodeFormatCode128",
    "EAN8": "PKBarcodeFormatCode128",
    "UPCA": "PKBarcodeFormatCode128",
    "UPCE": "PKBarcodeFormatCode128",
    "ITF": "PKBarcodeFormatCode128",
    "CODABAR": "PKBarcodeFormatCode128",
}


@pytest.mark.parametrize("name", [p.name for p in SAMPLES])
def test_declared_format_matches_the_detected_barcode_type(converted, name):
    """The real failure mode was a *valid* format that was the wrong one.

    A Code 128 detected under an unrecognised spelling silently fell back to
    PKBarcodeFormatQR — still a legal value, so a "is it a real format" check
    passes right over it. Compare against what was actually detected instead.
    """
    result = converted[name]
    for ticket, pass_json in zip(result["ticket_info"], result["passes"]):
        barcode = ticket.get("barcode")
        if not barcode:
            continue
        detected = str(barcode.get("type", "")).upper()
        expected = TYPE_TO_PK_FORMAT.get(detected)
        assert expected is not None, (
            f"{name}: barcode type {detected!r} is not a canonical name — "
            "a detector spelling is leaking through unnormalised"
        )
        declared = (pass_json.get("barcodes") or [{}])[0].get("format")
        assert declared == expected, (
            f"{name}: detected {detected} but pass declares {declared}"
        )


@pytest.mark.parametrize("name", [p.name for p in SAMPLES])
def test_pass_never_expires_before_it_starts(converted, name):
    """A 13→15 Aug hotel booking expired on the 14th, mid-stay."""
    for pass_json in converted[name]["passes"]:
        expiration = pass_json.get("expirationDate")
        if not expiration:
            continue
        dates = [
            field["value"]
            for field in _all_fields(pass_json)
            if field.get("key") in {"date", "end_date"} and _looks_like_date(field.get("value"))
        ]
        for value in dates:
            assert expiration[:10] >= value[:10], (
                f"{name}: expires {expiration[:10]} before {value[:10]}"
            )


def _looks_like_date(value: object) -> bool:
    text = str(value or "")
    return len(text) >= 10 and text[4] == "-" and text[7] == "-"


@pytest.mark.parametrize("name", [p.name for p in SAMPLES])
def test_every_pass_is_a_complete_signed_bundle(converted, name):
    """Catches packaging regressions: Wallet rejects an inconsistent manifest."""
    import hashlib

    for data in converted[name]["raw"]:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            names = set(archive.namelist())
            assert {"pass.json", "manifest.json", "signature", "icon.png"} <= names, (
                f"{name}: bundle missing files, has {sorted(names)}"
            )
            manifest = json.loads(archive.read("manifest.json"))
            for entry, digest in manifest.items():
                actual = hashlib.sha1(archive.read(entry)).hexdigest()
                assert actual == digest, f"{name}: manifest hash mismatch for {entry}"
            assert archive.read("signature"), f"{name}: empty signature"


@pytest.mark.parametrize("name", [p.name for p in SAMPLES])
def test_multi_pass_documents_do_not_repeat_one_barcode(converted, name):
    """Each pass of a booking must carry its own code, not a copy of the first."""
    result = converted[name]
    if len(result["passes"]) < 2:
        pytest.skip("single-pass document")

    messages = [
        (pass_json.get("barcodes") or [{}])[0].get("message")
        for pass_json in result["passes"]
    ]
    present = [m for m in messages if m]
    if len(present) < 2:
        pytest.skip("not enough barcodes to compare")
    assert len(set(present)) > 1, f"{name}: every pass carries the same barcode"


@pytest.mark.parametrize("name", [p.name for p in SAMPLES])
def test_serial_numbers_are_unique_within_a_document(converted, name):
    serials = [pass_json["serialNumber"] for pass_json in converted[name]["passes"]]

    assert len(serials) == len(set(serials)), f"{name}: duplicate serial numbers"


@pytest.mark.parametrize("sample", [p.name for p in SAMPLES])
def test_every_pass_is_something_passkit_would_accept(converted, sample):
    """The invariant that matters most, over every document we have.

    Not "the JSON looks right" — the archive itself, checked the way PassKit
    checks it. This is the assertion that would have caught the shipped
    "the data format is invalid" errors, and it now runs for every sample.
    """
    raw = converted[sample]["raw"]
    assert raw, f"{sample} produced no passes at all"
    for index, data in enumerate(raw):
        problems = validate_pkpass(data)
        assert not problems, f"{sample} pass {index + 1}: " + "; ".join(problems)
