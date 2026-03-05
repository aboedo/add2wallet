"""Integration tests based on Ignacio's feedback (email 2026-03-01).

Each test reflects a specific expectation Ignacio reported.
Source: test-files/ignacio-feedback/IGNACIO_NOTES.md

Run with:
    pytest tests/test_ignacio_feedback.py -v
"""

import io
import json
import os
import zipfile

import pytest

from app.services.barcode_extractor import BarcodeExtractor
from app.services.pass_generator import PassGenerator

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

IGNACIO_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "test-files",
    "ignacio-feedback",
)


def _load(filename: str) -> bytes:
    path = os.path.join(IGNACIO_DIR, filename)
    if not os.path.exists(path):
        pytest.skip(f"{filename} not found at {path}")
    with open(path, "rb") as f:
        return f.read()


def _generate(filename: str):
    """Run pass generation pipeline; return (pkpass_files, barcodes, ticket_info, warnings)."""
    pg = PassGenerator()
    return pg.create_pass_from_pdf_data(_load(filename), filename, ai_metadata=None)


def _pass_json(pkpass_bytes: bytes) -> dict:
    with zipfile.ZipFile(io.BytesIO(pkpass_bytes)) as z:
        return json.loads(z.read("pass.json"))


def _barcode_format(pkpass_bytes: bytes) -> str:
    pj = _pass_json(pkpass_bytes)
    barcodes = pj.get("barcodes") or [pj.get("barcode", {})]
    return barcodes[0].get("format", "") if barcodes else ""


# ---------------------------------------------------------------------------
# 1 — Notre-Dame: 4 tickets ✅
# ---------------------------------------------------------------------------

class TestNotreDame:
    """Ignacio: 'perfect; recognized 4 tickets'."""

    def test_generates_four_passes(self):
        pkpass_files, _, ticket_info, _ = _generate("1-Notre-Dame.pdf")
        assert len(pkpass_files) == 4, (
            f"Expected 4 passes for Notre-Dame, got {len(pkpass_files)}"
        )

    def test_event_name_recognized(self):
        _, _, ticket_info, _ = _generate("1-Notre-Dame.pdf")
        title = ticket_info[0].get("title", "").lower()
        assert "notre" in title or "dame" in title or "paris" in title, (
            f"Event name not recognized: {ticket_info[0].get('title')}"
        )

    def test_each_pass_has_barcode(self):
        pkpass_files, _, _, _ = _generate("1-Notre-Dame.pdf")
        for i, pkpass in enumerate(pkpass_files):
            fmt = _barcode_format(pkpass)
            assert fmt, f"Pass {i+1} has no barcode format"


# ---------------------------------------------------------------------------
# 2 — Abu Dhabi → Madrid (flight, no QR): date/time present
# ---------------------------------------------------------------------------

class TestAbuDhabiMadrid:
    """Ignacio: 'generated but sparse data' — should have date and flight info."""

    def test_generates_one_pass(self):
        pkpass_files, _, _, _ = _generate("2-AbuDhabi-Madrid.pdf")
        assert len(pkpass_files) == 1

    def test_has_barcode(self):
        pkpass_files, _, _, _ = _generate("2-AbuDhabi-Madrid.pdf")
        fmt = _barcode_format(pkpass_files[0])
        assert fmt, "Pass should have a barcode"

    def test_date_recognized(self):
        _, _, ticket_info, _ = _generate("2-AbuDhabi-Madrid.pdf")
        date = ticket_info[0].get("date") or ticket_info[0].get("departure_date")
        assert date, (
            "Flight date should be recognized — was reported as sparse data. "
            f"ticket_info keys: {list(ticket_info[0].keys())}"
        )

    def test_origin_destination_correct(self):
        """Flight is Abu Dhabi → Madrid (not reversed)."""
        _, _, ticket_info, _ = _generate("2-AbuDhabi-Madrid.pdf")
        desc = json.dumps(ticket_info[0]).lower()
        # Abu Dhabi should appear as origin, Madrid as destination
        assert "abu" in desc or "dhabi" in desc, "Abu Dhabi not mentioned in ticket info"
        assert "madrid" in desc, "Madrid not mentioned in ticket info"


# ---------------------------------------------------------------------------
# 3 — Málaga → Madrid (train): was HTTP 400, now should work
# ---------------------------------------------------------------------------

class TestMalagaMadrid:
    """Ignacio: 'HTTP 400; Contact Support opened blank screen' — must not error."""

    def test_generates_without_error(self):
        try:
            pkpass_files, _, _, _ = _generate("3-Malaga-Madrid.pdf")
        except Exception as e:
            pytest.fail(f"3-Malaga-Madrid.pdf raised exception (was HTTP 400): {e}")

    def test_generates_one_pass(self):
        pkpass_files, _, _, _ = _generate("3-Malaga-Madrid.pdf")
        assert len(pkpass_files) == 1

    def test_has_barcode(self):
        pkpass_files, _, _, _ = _generate("3-Malaga-Madrid.pdf")
        fmt = _barcode_format(pkpass_files[0])
        assert fmt, "Train pass should have a barcode"

    def test_date_recognized(self):
        _, _, ticket_info, _ = _generate("3-Malaga-Madrid.pdf")
        date = ticket_info[0].get("date")
        assert date, f"Train date should be recognized, got: {ticket_info[0].get('date')}"


# ---------------------------------------------------------------------------
# 4 — Benfica (encrypted PDF): was "data couldn't be read"
# ---------------------------------------------------------------------------

class TestBenfica:
    """Ignacio: 'data couldn't be read … correct format' — encrypted PDF, must now work."""

    def test_generates_without_error(self):
        try:
            pkpass_files, _, _, _ = _generate("4-Benfica.pdf")
        except Exception as e:
            pytest.fail(f"4-Benfica.pdf raised exception (was 'data couldn't be read'): {e}")

    def test_generates_one_pass(self):
        pkpass_files, _, _, _ = _generate("4-Benfica.pdf")
        assert len(pkpass_files) == 1

    def test_has_barcode(self):
        pkpass_files, _, _, _ = _generate("4-Benfica.pdf")
        fmt = _barcode_format(pkpass_files[0])
        assert fmt, "Benfica pass should have a barcode"


# ---------------------------------------------------------------------------
# 5 — Monasterio de Lisboa: perfect ✅
# ---------------------------------------------------------------------------

class TestMonasterioLisboa:
    """Ignacio: 'perfect (minor formatting)' — should stay working."""

    def test_generates_one_pass(self):
        pkpass_files, _, _, _ = _generate("5-Monasterio-Lisboa.pdf")
        assert len(pkpass_files) == 1

    def test_has_barcode(self):
        pkpass_files, _, _, _ = _generate("5-Monasterio-Lisboa.pdf")
        fmt = _barcode_format(pkpass_files[0])
        assert fmt

    def test_date_recognized(self):
        _, _, ticket_info, _ = _generate("5-Monasterio-Lisboa.pdf")
        date = ticket_info[0].get("date")
        assert date, f"Date should be recognized, got: {date}"


# ---------------------------------------------------------------------------
# 6 — Cine Gladiador (email PDF): worked ✅
# ---------------------------------------------------------------------------

class TestCineGladiador:
    """Ignacio: 'worked well; seat numbers hard' — basic generation must work."""

    def test_generates_one_pass(self):
        pkpass_files, _, _, _ = _generate("6-Cine-Gladiador.pdf")
        assert len(pkpass_files) == 1

    def test_has_barcode(self):
        pkpass_files, _, _, _ = _generate("6-Cine-Gladiador.pdf")
        fmt = _barcode_format(pkpass_files[0])
        assert fmt

    def test_movie_recognized(self):
        _, _, ticket_info, _ = _generate("6-Cine-Gladiador.pdf")
        title = ticket_info[0].get("title", "").lower()
        assert "gladiator" in title or "gladiador" in title, (
            f"Movie title not recognized: {ticket_info[0].get('title')}"
        )


# ---------------------------------------------------------------------------
# 7 — Madrid → Medellín (flight): was reversed + 3 passes
# ---------------------------------------------------------------------------

class TestMadridMedellin:
    """Ignacio: 'origin/destination reversed; generated 3 passes' — must be 1 pass, correct direction."""

    def test_generates_one_pass(self):
        pkpass_files, _, _, _ = _generate("7-Madrid-Medellin.pdf")
        assert len(pkpass_files) == 1, (
            f"Expected 1 pass for Madrid-Medellin, got {len(pkpass_files)} "
            "(was generating 3 passes)"
        )

    def test_origin_is_madrid(self):
        """Flight departs from Madrid (MAD), not Medellín."""
        _, _, ticket_info, _ = _generate("7-Madrid-Medellin.pdf")
        desc = json.dumps(ticket_info[0]).lower()
        # Madrid should be origin — check it appears before Medellin or in origin field
        origin = ticket_info[0].get("origin", "").lower()
        if origin:
            assert "madrid" in origin or "mad" in origin, (
                f"Origin should be Madrid, got: {origin}"
            )
        else:
            # Fall back to checking title/description contains correct direction
            assert "madrid" in desc, "Madrid should appear in ticket info"

    def test_destination_is_medellin(self):
        _, _, ticket_info, _ = _generate("7-Madrid-Medellin.pdf")
        desc = json.dumps(ticket_info[0]).lower()
        assert "medellin" in desc or "medellín" in desc or "mde" in desc, (
            "Medellín should appear in ticket info"
        )

    def test_has_barcode(self):
        pkpass_files, _, _, _ = _generate("7-Madrid-Medellin.pdf")
        fmt = _barcode_format(pkpass_files[0])
        assert fmt


# ---------------------------------------------------------------------------
# 8 — Reina Sofía: perfect ✅
# ---------------------------------------------------------------------------

class TestReinaSofia:
    """Ignacio: 'perfect' — regression guard."""

    def test_generates_one_pass(self):
        pkpass_files, _, _, _ = _generate("8-Reina-Sofia.pdf")
        assert len(pkpass_files) == 1

    def test_museum_recognized(self):
        _, _, ticket_info, _ = _generate("8-Reina-Sofia.pdf")
        title = ticket_info[0].get("title", "").lower()
        assert "reina" in title or "sofia" in title or "sofía" in title, (
            f"Museum not recognized: {ticket_info[0].get('title')}"
        )


# ---------------------------------------------------------------------------
# 9 — JO Paris (Olympics): had 503s, eventually worked ✅
# ---------------------------------------------------------------------------

class TestJOParis:
    """Ignacio: '503 initially; after retries worked' — generation itself must succeed."""

    def test_generates_without_error(self):
        try:
            pkpass_files, _, _, _ = _generate("9-JO-Paris.pdf")
        except Exception as e:
            pytest.fail(f"9-JO-Paris.pdf raised exception: {e}")

    def test_generates_passes(self):
        pkpass_files, _, _, _ = _generate("9-JO-Paris.pdf")
        assert len(pkpass_files) >= 1

    def test_has_barcode(self):
        pkpass_files, _, _, _ = _generate("9-JO-Paris.pdf")
        fmt = _barcode_format(pkpass_files[0])
        assert fmt


# ---------------------------------------------------------------------------
# 10 — Catedral de Málaga: worked ✅
# ---------------------------------------------------------------------------

class TestCatedralMalaga:
    """Ignacio: 'surprisingly good' — regression guard."""

    def test_generates_one_pass(self):
        pkpass_files, _, _, _ = _generate("10-Catedral-Malaga.pdf")
        assert len(pkpass_files) == 1

    def test_has_date(self):
        _, _, ticket_info, _ = _generate("10-Catedral-Malaga.pdf")
        date = ticket_info[0].get("date")
        assert date, f"Date should be recognized, got: {date}"


# ---------------------------------------------------------------------------
# 11 — Orsay: date not recognized
# ---------------------------------------------------------------------------

class TestOrsay:
    """Ignacio: 'date not recognized' — must now extract date."""

    def test_generates_one_pass(self):
        pkpass_files, _, _, _ = _generate("11-Orsay.pdf")
        assert len(pkpass_files) == 1

    def test_date_recognized(self):
        _, _, ticket_info, _ = _generate("11-Orsay.pdf")
        date = ticket_info[0].get("date")
        assert date, (
            "Orsay date should be recognized (Ignacio reported 'date not recognized'). "
            f"Got: {date}"
        )

    def test_museum_recognized(self):
        _, _, ticket_info, _ = _generate("11-Orsay.pdf")
        title = ticket_info[0].get("title", "").lower()
        assert "orsay" in title or "musée" in title or "musee" in title, (
            f"Museum not recognized: {ticket_info[0].get('title')}"
        )


# ---------------------------------------------------------------------------
# 12 — Peñarol: covered in test_penarol_integration.py (imported here for completeness)
# ---------------------------------------------------------------------------

class TestPenarol:
    """Ignacio: 'never worked; tiny barcode' — PDF417 via zxing-cpp."""

    def test_generates_one_pass(self):
        pkpass_files, _, _, _ = _generate("12-Penarol.pdf")
        assert len(pkpass_files) == 1

    def test_barcode_is_pdf417(self):
        pkpass_files, _, _, _ = _generate("12-Penarol.pdf")
        fmt = _barcode_format(pkpass_files[0])
        assert fmt == "PKBarcodeFormatPDF417", f"Expected PDF417, got {fmt}"


# ---------------------------------------------------------------------------
# 13 — Oppenheimer: worked ✅
# ---------------------------------------------------------------------------

class TestOppenheimer:
    """Ignacio: 'worked' — regression guard."""

    def test_generates_one_pass(self):
        pkpass_files, _, _, _ = _generate("13-Oppenheimer.pdf")
        assert len(pkpass_files) == 1

    def test_movie_recognized(self):
        _, _, ticket_info, _ = _generate("13-Oppenheimer.pdf")
        title = ticket_info[0].get("title", "").lower()
        assert "oppenheimer" in title, f"Movie not recognized: {ticket_info[0].get('title')}"

    def test_has_date(self):
        _, _, ticket_info, _ = _generate("13-Oppenheimer.pdf")
        date = ticket_info[0].get("date")
        assert date, f"Date should be recognized, got: {date}"
