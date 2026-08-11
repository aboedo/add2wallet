"""Every way a `.pkpass` can be malformed, and proof we catch it.

PassKit reports all of these the same way — "the data format is invalid" — and
that message is the whole diagnostic the user gets. It has bitten this project
more than once. So each check gets a test that breaks a *real, valid* pass in
exactly one way and asserts we notice, because a validator with no negative
cases is indistinguishable from `return []`.

The fixture is a signed pass built from the Fjord Tours itinerary, the document
that prompted this.
"""

from __future__ import annotations

import hashlib
import io
import json
import zipfile
from pathlib import Path

import pytest

from app.core.pkpass_validation import validate_pkpass


FIXTURE = Path(__file__).resolve().parent.parent.parent / "ios" / "Add2WalletTests" / "Resources" / "nutshell-leg.pkpass"


@pytest.fixture(scope="module")
def good_pass() -> bytes:
    if not FIXTURE.exists():
        pytest.skip(f"missing fixture {FIXTURE}")
    return FIXTURE.read_bytes()


def _rebuild(data: bytes, *, replace: dict[str, bytes] | None = None,
             drop: set[str] | None = None, rename: dict[str, str] | None = None) -> bytes:
    """Rewrite an archive with one thing changed, leaving the rest untouched."""
    replace = replace or {}
    drop = drop or set()
    rename = rename or {}
    source = zipfile.ZipFile(io.BytesIO(data))
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w") as target:
        for name in source.namelist():
            if name in drop:
                continue
            body = replace.get(name, source.read(name))
            target.writestr(rename.get(name, name), body)
    return out.getvalue()


def _pass_json(data: bytes) -> dict:
    return json.loads(zipfile.ZipFile(io.BytesIO(data)).read("pass.json"))


def _with_pass_json(data: bytes, payload: dict) -> bytes:
    """Swap in a new pass.json *and* fix its manifest hash.

    Otherwise every pass.json test would also trip the hash check and pass for
    the wrong reason.
    """
    body = json.dumps(payload).encode()
    manifest = json.loads(zipfile.ZipFile(io.BytesIO(data)).read("manifest.json"))
    manifest["pass.json"] = hashlib.sha1(body).hexdigest()
    return _rebuild(data, replace={
        "pass.json": body,
        "manifest.json": json.dumps(manifest).encode(),
    })


class TestAValidPassPasses:
    def test_the_real_thing_has_no_complaints(self, good_pass):
        assert validate_pkpass(good_pass) == []


class TestArchiveShape:
    def test_something_that_is_not_a_zip(self):
        problems = validate_pkpass(b"this is not a zip file")
        assert any("not a readable zip" in p for p in problems)

    def test_empty_input(self):
        assert validate_pkpass(b"") != []

    @pytest.mark.parametrize("required", ["pass.json", "manifest.json", "signature", "icon.png"])
    def test_each_required_file_is_required(self, good_pass, required):
        problems = validate_pkpass(_rebuild(good_pass, drop={required}))
        assert any(required in p for p in problems), problems

    def test_a_nested_directory_hides_everything_from_passkit(self, good_pass):
        broken = _rebuild(good_pass, rename={"pass.json": "Payload/pass.json"})
        assert any("nested path" in p for p in validate_pkpass(broken))

    def test_an_empty_signature_is_not_a_signature(self, good_pass):
        problems = validate_pkpass(_rebuild(good_pass, replace={"signature": b""}))
        assert any("signature is empty" in p for p in problems)


class TestManifest:
    def test_a_file_whose_hash_drifted_from_the_manifest(self, good_pass):
        """The classic: an asset regenerated after the manifest was written."""
        broken = _rebuild(good_pass, replace={"icon.png": b"\x89PNG\r\n\x1a\n" + b"different"})
        assert any("hash does not match" in p for p in validate_pkpass(broken))

    def test_a_file_present_but_unlisted(self, good_pass):
        manifest = json.loads(zipfile.ZipFile(io.BytesIO(good_pass)).read("manifest.json"))
        manifest.pop("icon.png")
        broken = _rebuild(good_pass, replace={"manifest.json": json.dumps(manifest).encode()})
        assert any("not in the manifest" in p for p in validate_pkpass(broken))

    def test_a_file_listed_but_absent(self, good_pass):
        manifest = json.loads(zipfile.ZipFile(io.BytesIO(good_pass)).read("manifest.json"))
        manifest["logo.png"] = "0" * 40
        broken = _rebuild(good_pass, replace={"manifest.json": json.dumps(manifest).encode()})
        assert any("not in the archive" in p for p in validate_pkpass(broken))

    def test_an_unparseable_manifest(self, good_pass):
        broken = _rebuild(good_pass, replace={"manifest.json": b"{not json"})
        assert any("manifest.json is not valid" in p for p in validate_pkpass(broken))


class TestPassJSON:
    def test_unparseable(self, good_pass):
        broken = _rebuild(good_pass, replace={"pass.json": b"{nope"})
        # The hash check fires too; what matters is that we refuse it.
        assert validate_pkpass(broken) != []

    @pytest.mark.parametrize("key", [
        "passTypeIdentifier", "serialNumber", "teamIdentifier",
        "organizationName", "description",
    ])
    def test_each_required_key_is_required(self, good_pass, key):
        payload = _pass_json(good_pass)
        payload.pop(key)
        problems = validate_pkpass(_with_pass_json(good_pass, payload))
        assert any(key in p for p in problems), problems

    def test_a_required_key_present_but_blank_is_still_missing(self, good_pass):
        payload = _pass_json(good_pass)
        payload["description"] = "   "
        assert any("description" in p for p in validate_pkpass(_with_pass_json(good_pass, payload)))

    def test_wrong_format_version(self, good_pass):
        payload = _pass_json(good_pass)
        payload["formatVersion"] = 2
        assert any("formatVersion" in p for p in validate_pkpass(_with_pass_json(good_pass, payload)))

    def test_no_style_at_all(self, good_pass):
        payload = _pass_json(good_pass)
        for style in ("eventTicket", "generic", "boardingPass", "coupon", "storeCard"):
            payload.pop(style, None)
        assert any("pass style" in p for p in validate_pkpass(_with_pass_json(good_pass, payload)))

    def test_two_styles_at_once(self, good_pass):
        payload = _pass_json(good_pass)
        payload["generic"] = payload.get("generic") or {}
        payload["eventTicket"] = {}
        assert any("pass style" in p for p in validate_pkpass(_with_pass_json(good_pass, payload)))


class TestDates:
    """A date without a zone does not identify an instant, and PassKit says so."""

    @pytest.mark.parametrize("value", [
        "2026-08-18",              # date only — the shape our extractor produces
        "2026-08-18 08:29:00",     # space separator, no zone
        "2026-08-18T08:29:00",     # no zone
        "18/08/2026",
        "not a date",
    ])
    def test_rejected_date_shapes(self, good_pass, value):
        payload = _pass_json(good_pass)
        payload["relevantDate"] = value
        problems = validate_pkpass(_with_pass_json(good_pass, payload))
        assert any("relevantDate" in p for p in problems), problems

    @pytest.mark.parametrize("value", [
        "2026-08-18T08:29:00Z",
        "2026-08-18T08:29:00+02:00",
        "2026-08-18T08:29:00-0300",
        "2026-08-18T08:29Z",
    ])
    def test_accepted_date_shapes(self, good_pass, value):
        payload = _pass_json(good_pass)
        payload["relevantDate"] = value
        assert not any("relevantDate" in p for p in validate_pkpass(_with_pass_json(good_pass, payload)))


class TestFieldValues:
    """A dict reaching a field renders as its Python repr on the pass. Shipped once."""

    def test_a_dict_as_a_field_value(self, good_pass):
        payload = _pass_json(good_pass)
        style = next(k for k in ("generic", "eventTicket", "boardingPass", "coupon", "storeCard")
                     if payload.get(k) is not None)
        payload[style] = {"primaryFields": [{"key": "seat", "label": "Seat",
                                             "value": {"car": 1, "seats": [9, 10]}}]}
        problems = validate_pkpass(_with_pass_json(good_pass, payload))
        assert any("must be a string or number" in p for p in problems), problems

    def test_a_string_value_is_fine(self, good_pass):
        payload = _pass_json(good_pass)
        style = next(k for k in ("generic", "eventTicket", "boardingPass", "coupon", "storeCard")
                     if payload.get(k) is not None)
        payload[style] = {"primaryFields": [{"key": "seat", "label": "Seat", "value": "Car 1, Seat 9"}]}
        assert not any("string or number" in p for p in validate_pkpass(_with_pass_json(good_pass, payload)))


class TestImages:
    def test_a_png_that_is_not_a_png(self, good_pass):
        data = _rebuild(good_pass, replace={"icon.png": b"GIF89a-nope"})
        manifest = json.loads(zipfile.ZipFile(io.BytesIO(data)).read("manifest.json"))
        manifest["icon.png"] = hashlib.sha1(b"GIF89a-nope").hexdigest()
        data = _rebuild(data, replace={"manifest.json": json.dumps(manifest).encode()})
        assert any("is not a PNG" in p for p in validate_pkpass(data))

    def test_an_empty_image(self, good_pass):
        data = _rebuild(good_pass, replace={"icon.png": b""})
        manifest = json.loads(zipfile.ZipFile(io.BytesIO(data)).read("manifest.json"))
        manifest["icon.png"] = hashlib.sha1(b"").hexdigest()
        data = _rebuild(data, replace={"manifest.json": json.dumps(manifest).encode()})
        assert any("icon.png is empty" in p for p in validate_pkpass(data))


class TestTheBuilderActuallyUsesIt:
    """A validator nobody calls is a comment.

    This is the wiring test: it forces the packaging step to emit a broken
    archive and asserts the build refuses rather than returning it. Without it,
    deleting the one line in `WalletPassBuilder.build` would leave every test
    above passing.
    """

    def test_a_broken_package_fails_the_build_instead_of_shipping(self, monkeypatch):
        from app.core.config import get_settings
        from app.core.errors import ProcessingError
        from app.core.models import (
            AnalysisResult,
            DocumentKind,
            StructuredMetadata,
            ValidatedUpload,
        )
        from app.core.pass_builder import WalletPassBuilder

        builder = WalletPassBuilder(get_settings())
        monkeypatch.setattr(
            WalletPassBuilder, "_package", lambda *a, **k: b"not a zip at all"
        )

        upload = ValidatedUpload(
            filename="x.pdf",
            content_type="application/pdf",
            kind=DocumentKind.pdf,
            data=b"%PDF-1.4",
            extension="pdf",
        )
        analysis = AnalysisResult(metadata=StructuredMetadata(title="Anything"))

        with pytest.raises(ProcessingError) as caught:
            builder.build(upload, analysis)
        assert "invalid pkpass" in str(caught.value)
