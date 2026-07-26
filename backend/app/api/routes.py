from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
import re
from typing import Optional

from fastapi import APIRouter, File, Form, Header, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse, Response

from app.core.errors import FileTooLargeError, UnauthorizedError
from app.core.models import StoredJob
from app.models.responses import StatusResponse, UploadResponse


ENHANCED_METADATA_FIELDS = {
    "event_type",
    "event_name",
    "title",
    "description",
    "date",
    "time",
    "duration",
    "venue_name",
    "venue_address",
    "city",
    "state_country",
    "latitude",
    "longitude",
    "organizer",
    "performer_artist",
    "seat_info",
    "barcode_data",
    "price",
    "confirmation_number",
    "gate_info",
    "event_description",
    "venue_type",
    "capacity",
    "website",
    "phone",
    "nearby_landmarks",
    "public_transport",
    "parking_info",
    "age_restriction",
    "dress_code",
    "weather_considerations",
    "amenities",
    "accessibility",
    "ai_processed",
    "confidence_score",
    "processing_timestamp",
    "model_used",
    "enrichment_completed",
    "background_color",
    "foreground_color",
    "label_color",
    "multiple_events",
    "upcoming_events",
    "venue_place_id",
    "performer_names",
    "exhibit_name",
    "has_assigned_seating",
    "event_urls",
}

LIST_FIELDS = {"nearby_landmarks", "amenities", "upcoming_events", "performer_names"}


def create_router() -> APIRouter:
    router = APIRouter()

    @router.get("/")
    async def root() -> dict[str, str]:
        return {"message": "Add2Wallet API is running", "version": "1.0.0"}

    @router.post("/api/v1/conversions", response_model=UploadResponse)
    async def create_conversion(
        request: Request,
        file: UploadFile = File(...),
        user_id: str = Form(...),
        session_token: str = Form(...),
        is_retry: bool = Form(False),
        is_demo: bool = Form(False),
        x_api_key: Optional[str] = Header(None),
    ) -> UploadResponse:
        _require_api_key(request, x_api_key)
        data = await _read_upload_limited(file, request.app.state.settings.max_upload_bytes)
        job = await request.app.state.pipeline.convert(
            filename=file.filename,
            content_type=file.content_type,
            data=data,
            user_id=user_id,
            session_token=session_token,
            is_retry=is_retry,
            is_demo=is_demo,
        )
        return _upload_response(job)

    @router.post("/upload", response_model=UploadResponse)
    async def upload_alias(
        request: Request,
        file: UploadFile = File(...),
        user_id: str = Form(...),
        session_token: str = Form(...),
        is_retry: bool = Form(False),
        is_demo: bool = Form(False),
        x_api_key: Optional[str] = Header(None),
    ) -> UploadResponse:
        return await create_conversion(request, file, user_id, session_token, is_retry, is_demo, x_api_key)

    @router.post("/upload/v2", response_model=UploadResponse)
    async def upload_v2_alias(
        request: Request,
        file: UploadFile = File(...),
        user_id: str = Form(...),
        session_token: str = Form(...),
        is_retry: bool = Form(False),
        is_demo: bool = Form(False),
        x_api_key: Optional[str] = Header(None),
    ) -> UploadResponse:
        return await create_conversion(request, file, user_id, session_token, is_retry, is_demo, x_api_key)

    @router.get("/status/{job_id}", response_model=StatusResponse)
    async def get_status(request: Request, job_id: str, authorization: Optional[str] = Header(None)) -> StatusResponse:
        job = _get_job(request, job_id)
        return StatusResponse(
            job_id=job.job_id,
            status=job.status,
            progress=job.progress,
            result_url=f"/pass/{job.job_id}" if job.status == "completed" else None,
            ai_metadata=_sanitize_metadata(_metadata_for_job(job)),
            warnings=job.warnings or None,
        )

    @router.get("/pass/{job_id}")
    async def download_pass(
        request: Request,
        job_id: str,
        ticket_number: Optional[int] = None,
        authorization: Optional[str] = Header(None),
    ) -> Response:
        job = _get_job(request, job_id)
        if job.status != "completed":
            raise HTTPException(status_code=400, detail="Pass is not ready yet")
        if not job.pass_paths:
            raise HTTPException(status_code=404, detail="No pass files found")

        if ticket_number is not None:
            if ticket_number < 1 or ticket_number > len(job.pass_paths):
                raise HTTPException(status_code=400, detail=f"Invalid ticket number. Available: 1-{len(job.pass_paths)}")
            index = ticket_number - 1
        else:
            index = 0

        path = job.pass_paths[index]
        if not path.exists():
            raise HTTPException(status_code=404, detail="Pass file not found")

        filename_suffix = f"_ticket_{index + 1}" if len(job.pass_paths) > 1 else ""
        base_filename = _safe_download_stem(job.filename)
        return FileResponse(
            path,
            media_type="application/vnd.apple.pkpass",
            filename=f"{base_filename}{filename_suffix}.pkpass",
        )

    @router.get("/tickets/{job_id}")
    async def list_tickets(request: Request, job_id: str, authorization: Optional[str] = Header(None)) -> dict:
        job = _get_job(request, job_id)
        job_metadata = job.ai_metadata or {}
        return {
            "job_id": job.job_id,
            "ticket_count": job.ticket_count,
            "barcode_count": job.barcode_count,
            # Group identity so related passes can be shown together.
            "group_id": job_metadata.get("group_id"),
            "group_name": job_metadata.get("group_name"),
            "tickets": [
                {
                    "ticket_number": ticket["ticket_number"],
                    "title": ticket["title"],
                    "description": ticket["description"],
                    "download_url": f"/pass/{job.job_id}?ticket_number={ticket['ticket_number']}",
                    "has_barcode": ticket.get("barcode") is not None,
                    "barcode_type": ticket["barcode"]["type"] if ticket.get("barcode") else None,
                    # Per-leg detail: what makes one ticket of a booking
                    # distinguishable from the next.
                    "segment": (ticket.get("metadata") or {}).get("segment"),
                    "route": (ticket.get("metadata") or {}).get("route"),
                    "metadata": ticket.get("metadata"),
                }
                for ticket in job.ticket_info
            ],
        }

    @router.get("/passes")
    async def list_passes(request: Request, authorization: Optional[str] = Header(None)) -> dict:
        return {
            "passes": [
                {
                    "job_id": job.job_id,
                    "filename": job.filename,
                    "status": job.status,
                    "ticket_count": job.ticket_count or 1,
                    "barcode_count": job.barcode_count,
                }
                for job in request.app.state.store.list()
            ]
        }

    @router.get("/healthz")
    async def healthz() -> dict[str, str]:
        return {"status": "ok"}

    @router.get("/health")
    async def health(request: Request) -> dict:
        settings = request.app.state.settings
        store = request.app.state.store
        signer = request.app.state.signer
        return {
            "status": "healthy",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "version": request.app.version,
            "services": {
                "openai": "enabled" if settings.openai_api_key else "disabled",
                "revenuecat": "enabled" if settings.revenuecat_secret_key else "disabled",
                "signing": "enabled" if signer.signing_enabled else "disabled",
                "storage": "ok",
            },
            "jobs": {
                "active": len(store.jobs),
                "ttl_seconds": settings.job_ttl_seconds,
            },
            "limits": {"max_upload_bytes": settings.max_upload_bytes},
        }

    @router.get("/demo-pass")
    async def get_demo_pass() -> FileResponse:
        demo_path = Path(__file__).resolve().parents[1] / "demo_eiffel_future.pkpass"
        if not demo_path.exists():
            raise HTTPException(status_code=404, detail="Demo pass not found")
        return FileResponse(
            demo_path,
            media_type="application/vnd.apple.pkpass",
            filename="demo_eiffel_future.pkpass",
        )

    @router.get("/share/{token}")
    async def handle_universal_link_sharing(token: str) -> RedirectResponse:
        _validate_uuid(token)
        return RedirectResponse(url=f"add2wallet://share/{token}", status_code=302)

    @router.get("/share/{token}/metadata")
    async def get_sharing_metadata(token: str) -> JSONResponse:
        _validate_uuid(token)
        return JSONResponse(
            {
                "token": token,
                "status": "valid",
                "message": "Open the Add2Wallet app to process this PDF",
            }
        )

    @router.get("/.well-known/apple-app-site-association")
    async def apple_app_site_association() -> Response:
        association_file_path = Path(__file__).resolve().parents[2] / "apple-app-site-association"
        if not association_file_path.exists():
            raise HTTPException(status_code=404, detail="Association file not found")
        return Response(
            content=association_file_path.read_text(),
            media_type="application/json",
            headers={"Content-Type": "application/json"},
        )

    return router


def _require_api_key(request: Request, api_key: str | None) -> None:
    if api_key != request.app.state.settings.api_key:
        raise UnauthorizedError()


async def _read_upload_limited(file: UploadFile, max_bytes: int) -> bytes:
    total = 0
    chunks: list[bytes] = []
    try:
        while True:
            chunk = await file.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > max_bytes:
                raise FileTooLargeError(max_bytes)
            chunks.append(chunk)
        return b"".join(chunks)
    finally:
        await file.close()


def _get_job(request: Request, job_id: str) -> StoredJob:
    job = request.app.state.store.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")
    return job


def _upload_response(job: StoredJob) -> UploadResponse:
    return UploadResponse(
        job_id=job.job_id,
        status=job.status,
        pass_url=f"/pass/{job.job_id}" if job.status == "completed" else None,
        ai_metadata=_sanitize_metadata(_metadata_for_job(job)),
        ticket_count=job.ticket_count or None,
        warnings=job.warnings or None,
        remaining_passes=job.remaining_passes,
    )


def _metadata_for_job(job: StoredJob) -> dict | None:
    if job.ticket_info:
        return job.ticket_info[0].get("metadata") or job.ai_metadata
    return job.ai_metadata


def _sanitize_metadata(raw: dict | None) -> dict | None:
    if raw is None:
        return None
    clean = {}
    for key, value in raw.items():
        if key not in ENHANCED_METADATA_FIELDS:
            continue
        if key in LIST_FIELDS and value is not None and not isinstance(value, list):
            clean[key] = None
            continue
        clean[key] = value
    return clean


def _validate_uuid(token: str) -> None:
    import uuid

    try:
        uuid.UUID(token)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid sharing token")


def _safe_download_stem(filename: str) -> str:
    stem = Path(filename.replace("\\", "/")).name
    stem = Path(stem).stem or "pass"
    stem = re.sub(r"[^A-Za-z0-9._ -]+", "_", stem).strip(" ._")
    return stem[:80] or "pass"
