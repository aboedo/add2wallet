import io
import os
import zipfile
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from PIL import Image
from PyPDF2 import PdfWriter

from app.main import app


client = TestClient(app)
HEADERS = {"X-API-Key": os.getenv("API_KEY", "development-api-key")}
FORM = {"user_id": "test-user", "session_token": "test-token", "is_demo": "true"}


def _pdf_bytes() -> bytes:
    writer = PdfWriter()
    writer.add_blank_page(width=200, height=200)
    buf = io.BytesIO()
    writer.write(buf)
    return buf.getvalue()


def _image_bytes(fmt: str) -> bytes:
    image = Image.new("RGB", (80, 80), (22, 82, 96))
    buf = io.BytesIO()
    image.save(buf, format=fmt)
    return buf.getvalue()


def _heic_like_bytes() -> bytes:
    # Read a committed fixture instead of encoding HEIC here: the libheif/x265
    # encoder segfaults the interpreter on some hosts, which would take the
    # whole test session down at collection time. Decoding is what the backend
    # actually does, and that path is exercised by posting these bytes.
    return (Path(__file__).parent / "fixtures" / "sample.heic").read_bytes()


def _post_conversion(name: str, payload: bytes, content_type: str, path: str = "/api/v1/conversions"):
    return client.post(
        path,
        files={"file": (name, payload, content_type)},
        data=FORM,
        headers=HEADERS,
    )


def test_versioned_endpoint_accepts_pdf_by_magic_bytes_not_filename():
    response = _post_conversion("ticket.notpdf", _pdf_bytes(), "application/octet-stream")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "completed"
    assert body["pass_url"].startswith("/pass/")
    assert body["ticket_count"] == 1
    assert body["ai_metadata"]["title"]


@pytest.mark.parametrize(
    ("filename", "payload", "content_type"),
    [
        ("photo.jpg", _image_bytes("JPEG"), "image/jpeg"),
        ("photo.png", _image_bytes("PNG"), "image/png"),
        ("photo.heic", _heic_like_bytes(), "image/heic"),
        ("photo.heif", _heic_like_bytes(), "image/heif"),
    ],
)
def test_versioned_endpoint_accepts_supported_image_magic_bytes(filename, payload, content_type):
    response = _post_conversion(filename, payload, content_type)

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "completed"
    assert body["ticket_count"] == 1


def test_compatibility_upload_aliases_use_same_pipeline():
    for path in ["/upload", "/upload/v2"]:
        response = _post_conversion("alias.pdf", _pdf_bytes(), "application/pdf", path=path)
        assert response.status_code == 200
        assert response.json()["status"] == "completed"


def test_unsupported_file_returns_typed_http_error():
    response = _post_conversion("ticket.pdf", b"not a real supported file", "application/pdf")

    assert response.status_code == 400
    assert response.json()["error"] == response.json()["detail"]["message"]
    assert response.json()["detail"]["code"] == "unsupported_file"


def test_mime_type_must_match_magic_bytes():
    response = _post_conversion("photo.pdf", _image_bytes("PNG"), "application/pdf")

    assert response.status_code == 400
    assert response.json()["error"] == "File content does not match declared MIME type"
    assert response.json()["detail"]["code"] == "unsupported_file"


def test_pdf_magic_bytes_must_parse_as_valid_pdf():
    response = _post_conversion("truncated.pdf", b"%PDF-not-really-a-pdf", "application/pdf")

    assert response.status_code == 400
    assert response.json()["detail"]["code"] == "unsupported_file"
    assert "Invalid PDF" in response.json()["error"]


def test_heic_magic_bytes_must_decode_as_valid_image():
    fake_heic = b"\x00\x00\x00\x18ftypheic\x00\x00\x00\x00heicmif1" + (b"\x00" * 128)

    response = _post_conversion("photo.heic", fake_heic, "image/heic")

    assert response.status_code == 400
    assert response.json()["detail"]["code"] == "unsupported_file"
    assert response.json()["error"] == "Invalid image file"


def test_oversized_file_returns_http_error_not_failed_200():
    response = _post_conversion("huge.pdf", b"%PDF-" + (b"0" * (10 * 1024 * 1024 + 1)), "application/pdf")

    assert response.status_code == 413
    assert response.json()["error"] == "File size exceeds 10MB limit"
    assert response.json()["detail"]["code"] == "file_too_large"


def test_pass_download_and_ticket_contract():
    upload_response = _post_conversion("ticket.pdf", _pdf_bytes(), "application/pdf")
    job_id = upload_response.json()["job_id"]

    tickets_response = client.get(f"/tickets/{job_id}")
    assert tickets_response.status_code == 200
    tickets = tickets_response.json()
    assert tickets["ticket_count"] == 1
    assert tickets["tickets"][0]["download_url"] == f"/pass/{job_id}?ticket_number=1"

    pass_response = client.get(f"/pass/{job_id}")
    assert pass_response.status_code == 200
    assert pass_response.headers["content-type"] == "application/vnd.apple.pkpass"
    with zipfile.ZipFile(io.BytesIO(pass_response.content)) as archive:
        assert "pass.json" in archive.namelist()
        assert "manifest.json" in archive.namelist()


def test_download_filename_is_sanitized():
    upload_response = _post_conversion("../bad\r\nname.pdf", _pdf_bytes(), "application/pdf")
    job_id = upload_response.json()["job_id"]

    pass_response = client.get(f"/pass/{job_id}")

    assert pass_response.status_code == 200
    disposition = pass_response.headers["content-disposition"]
    assert "\r" not in disposition
    assert "\n" not in disposition
    assert "../" not in disposition
