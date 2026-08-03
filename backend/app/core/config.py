from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv


load_dotenv()


@dataclass(frozen=True)
class Settings:
    api_key: str
    max_upload_bytes: int
    upload_dir: Path
    job_ttl_seconds: int
    cleanup_interval_seconds: int
    openai_api_key: str | None
    openai_model: str
    revenuecat_secret_key: str | None
    revenuecat_project_id: str | None
    pass_type_identifier: str
    team_identifier: str
    app_store_id: int | None
    cors_origins: tuple[str, ...]


def get_settings() -> Settings:
    app_store_id = None
    raw_store_id = os.getenv("APP_STORE_ID")
    if raw_store_id:
        try:
            app_store_id = int(raw_store_id)
        except ValueError:
            app_store_id = None

    origins = tuple(
        origin.strip()
        for origin in os.getenv("CORS_ORIGINS", "*").split(",")
        if origin.strip()
    )

    return Settings(
        api_key=os.getenv("API_KEY", "development-api-key"),
        max_upload_bytes=int(os.getenv("MAX_UPLOAD_BYTES", str(10 * 1024 * 1024))),
        upload_dir=Path(os.getenv("UPLOAD_DIR", "uploads")),
        job_ttl_seconds=int(os.getenv("JOB_TTL_SECONDS", "1800")),
        cleanup_interval_seconds=int(os.getenv("CLEANUP_INTERVAL_SECONDS", "300")),
        openai_api_key=os.getenv("OPENAI_API_KEY"),
        openai_model=os.getenv("OPENAI_MODEL", "gpt-5.6-luna"),
        revenuecat_secret_key=os.getenv("REVENUECAT_SECRET_KEY"),
        revenuecat_project_id=os.getenv("REVENUECAT_PROJECT_ID", "projd85d45ec"),
        pass_type_identifier=os.getenv("PASS_TYPE_IDENTIFIER", "pass.com.andresboedo.add2wallet"),
        team_identifier=os.getenv("TEAM_IDENTIFIER", "H9DPH4DQG7"),
        app_store_id=app_store_id,
        cors_origins=origins or ("*",),
    )

