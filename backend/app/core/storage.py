from __future__ import annotations

import time
from pathlib import Path

from app.core.config import Settings
from app.core.models import PassArtifact, StoredJob, ValidatedUpload


class JobStore:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.settings.upload_dir.mkdir(parents=True, exist_ok=True)
        self.jobs: dict[str, StoredJob] = {}

    def create_processing_job(self, job_id: str, user_id: str, upload: ValidatedUpload) -> StoredJob:
        file_path = self.settings.upload_dir / f"{job_id}.{upload.extension}"
        file_path.write_bytes(upload.data)
        job = StoredJob(
            job_id=job_id,
            user_id=user_id,
            status="processing",
            progress=10,
            filename=upload.filename,
            created_at=time.time(),
            file_path=file_path,
        )
        self.jobs[job_id] = job
        return job

    def save_artifacts(
        self,
        job_id: str,
        artifacts: list[PassArtifact],
        detected_barcodes: list[dict],
        metadata: dict,
        warnings: list[str],
    ) -> StoredJob:
        job = self.jobs[job_id]
        job.pass_paths = []
        pass_paths = job.pass_paths
        ticket_info: list[dict] = []
        for artifact in artifacts:
            suffix = f"_ticket_{artifact.ticket_number}" if len(artifacts) > 1 else ""
            path = self.settings.upload_dir / f"{job_id}{suffix}.pkpass"
            path.write_bytes(artifact.data)
            pass_paths.append(path)
            barcode = artifact.barcode.model_dump() if artifact.barcode else None
            ticket_info.append(
                {
                    "ticket_number": artifact.ticket_number,
                    "title": artifact.title,
                    "description": artifact.description,
                    "barcode": barcode,
                    "metadata": artifact.metadata,
                }
            )

        job.progress = max(job.progress, 90)
        job.ticket_info = ticket_info
        job.detected_barcodes = detected_barcodes
        job.barcode_count = len(detected_barcodes)
        job.ticket_count = len(artifacts)
        job.ai_metadata = metadata
        job.warnings = warnings
        return job

    def complete_job(self, job_id: str, remaining_passes: int | None) -> StoredJob:
        job = self.jobs[job_id]
        job.status = "completed"
        job.progress = 100
        job.remaining_passes = remaining_passes
        return job

    def fail_job(self, job_id: str, error: str) -> None:
        job = self.jobs.get(job_id)
        if not job:
            return
        for path in [job.file_path, *job.pass_paths]:
            try:
                path.unlink(missing_ok=True)
            except Exception:
                pass
        job.status = "failed"
        job.progress = 0
        job.error = error

    def get(self, job_id: str) -> StoredJob | None:
        return self.jobs.get(job_id)

    def list(self) -> list[StoredJob]:
        return list(self.jobs.values())

    def cleanup_expired(self) -> int:
        cutoff = time.time() - self.settings.job_ttl_seconds
        removed = 0
        for job_id, job in list(self.jobs.items()):
            if job.created_at >= cutoff:
                continue
            for path in [job.file_path, *job.pass_paths]:
                try:
                    path.unlink(missing_ok=True)
                except Exception:
                    pass
            self.jobs.pop(job_id, None)
            removed += 1

        for path in self.settings.upload_dir.glob("*"):
            try:
                if path.is_file() and path.stat().st_mtime < cutoff:
                    path.unlink(missing_ok=True)
            except Exception:
                pass
        return removed

    def cleanup_all(self) -> None:
        for job in list(self.jobs.values()):
            for path in [job.file_path, *job.pass_paths]:
                try:
                    path.unlink(missing_ok=True)
                except Exception:
                    pass
        self.jobs.clear()
