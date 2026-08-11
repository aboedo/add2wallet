"""Does this `.pkpass` satisfy what PassKit demands of it?

Everything that validated a pass before this ran on the *inputs*:
`validate_pass` checks the `PassJSON` model before the archive exists. That
misses the entire class of bug that actually reaches people — the archive is
assembled after the JSON is approved, and an archive can be malformed while its
JSON is perfect. A missing `icon.png`, a manifest hash that drifted from the
file it names, a date without a timezone: PassKit refuses all of them with the
same opaque "the data format is invalid", and nothing on our side had an
opinion about any of them.

So this validates the bytes we are about to hand over, and it runs on every
pass before it leaves the builder. A pass that fails here is a bug in us, and
it should surface as a loud server-side error rather than as a file the device
silently rejects.

Every check below is something PassKit rejects. None of them is style.
"""

from __future__ import annotations

import hashlib
import io
import json
import re
import zipfile


# Apple requires an icon; a pass without one is refused on add. The rest of the
# image set is optional, so their absence is not an error here.
REQUIRED_FILES = {"pass.json", "manifest.json", "signature", "icon.png"}

REQUIRED_KEYS = (
    "formatVersion",
    "passTypeIdentifier",
    "serialNumber",
    "teamIdentifier",
    "organizationName",
    "description",
)

STYLE_KEYS = ("eventTicket", "generic", "boardingPass", "coupon", "storeCard")

# Files the manifest deliberately does not cover: it cannot hash itself, and
# the signature is computed *over* the manifest.
UNMANIFESTED = {"manifest.json", "signature"}

# W3C date-time, which is what Apple's spec points at: a full date and time
# with an explicit offset. "2026-08-18" alone is rejected, and so is a local
# time with no zone, because neither identifies an instant.
W3C_DATE = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})$"
)

DATE_FIELDS = ("relevantDate", "expirationDate")

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def validate_pkpass(data: bytes) -> list[str]:
    """Return every reason PassKit would refuse this archive. Empty means good."""
    errors: list[str] = []

    try:
        archive = zipfile.ZipFile(io.BytesIO(data))
    except (zipfile.BadZipFile, OSError) as exc:
        return [f"not a readable zip archive: {exc}"]

    names = archive.namelist()

    for required in sorted(REQUIRED_FILES):
        if required not in names:
            errors.append(f"missing {required}")

    # A pkpass is a flat bundle. A nested directory means the archive was built
    # from the wrong root, and everything inside it is invisible to PassKit.
    for name in names:
        if "/" in name.rstrip("/"):
            errors.append(f"nested path not allowed in a pkpass: {name}")

    if len(names) != len(set(names)):
        errors.append("archive contains duplicate entries")

    errors.extend(_validate_pass_json(archive, names))
    errors.extend(_validate_manifest(archive, names))
    errors.extend(_validate_images(archive, names))

    if "signature" in names and not archive.read("signature"):
        errors.append("signature is empty")

    return errors


def _validate_pass_json(archive: zipfile.ZipFile, names: list[str]) -> list[str]:
    if "pass.json" not in names:
        return []

    errors: list[str] = []
    try:
        payload = json.loads(archive.read("pass.json").decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        return [f"pass.json is not valid UTF-8 JSON: {exc}"]

    if not isinstance(payload, dict):
        return ["pass.json must be a JSON object"]

    for key in REQUIRED_KEYS:
        value = payload.get(key)
        if value is None or (isinstance(value, str) and not value.strip()):
            errors.append(f"pass.json is missing {key}")

    if payload.get("formatVersion") != 1:
        errors.append(f"formatVersion must be 1, got {payload.get('formatVersion')!r}")

    styles = [key for key in STYLE_KEYS if payload.get(key) is not None]
    if len(styles) != 1:
        errors.append(f"exactly one pass style is required, found {styles}")

    for field in DATE_FIELDS:
        value = payload.get(field)
        if value is not None and not W3C_DATE.match(str(value)):
            errors.append(f"{field} is not a W3C date-time with a timezone: {value!r}")

    # Every value a pass field displays has to be a string or a number. A dict
    # or a list here renders as its Python repr on the pass, which has shipped.
    errors.extend(_validate_field_values(payload, styles))

    return errors


def _validate_field_values(payload: dict, styles: list[str]) -> list[str]:
    errors: list[str] = []
    for style in styles:
        groups = payload.get(style)
        if not isinstance(groups, dict):
            continue
        for group_name, fields in groups.items():
            if not isinstance(fields, list):
                continue
            for field in fields:
                if not isinstance(field, dict):
                    continue
                value = field.get("value")
                if isinstance(value, (dict, list)):
                    key = field.get("key", "?")
                    errors.append(
                        f"{style}.{group_name}[{key}].value must be a string or number, "
                        f"got {type(value).__name__}"
                    )
    return errors


def _validate_manifest(archive: zipfile.ZipFile, names: list[str]) -> list[str]:
    if "manifest.json" not in names:
        return []

    try:
        manifest = json.loads(archive.read("manifest.json").decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        return [f"manifest.json is not valid UTF-8 JSON: {exc}"]

    if not isinstance(manifest, dict):
        return ["manifest.json must be a JSON object"]

    errors: list[str] = []
    payload_files = {name for name in names if name not in UNMANIFESTED}

    for name in sorted(payload_files):
        expected = manifest.get(name)
        if expected is None:
            errors.append(f"{name} is in the archive but not in the manifest")
            continue
        actual = hashlib.sha1(archive.read(name)).hexdigest()
        if actual != expected:
            errors.append(
                f"{name} hash does not match the manifest "
                f"(manifest {expected}, file {actual})"
            )

    for name in sorted(set(manifest) - payload_files):
        errors.append(f"{name} is in the manifest but not in the archive")

    return errors


def _validate_images(archive: zipfile.ZipFile, names: list[str]) -> list[str]:
    errors: list[str] = []
    for name in sorted(names):
        if not name.endswith(".png"):
            continue
        body = archive.read(name)
        if not body:
            errors.append(f"{name} is empty")
        elif not body.startswith(PNG_MAGIC):
            errors.append(f"{name} is not a PNG")
    return errors
