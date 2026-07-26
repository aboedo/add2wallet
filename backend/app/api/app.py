from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.routes import create_router
from app.core.config import Settings, get_settings
from app.core.errors import ConversionError
from app.core.logging import setup_logging
from app.core.pipeline import ConversionPipeline
from app.core.storage import JobStore
from app.services.v2.pass_signer import get_signer


logger = logging.getLogger(__name__)


def create_app(settings: Settings | None = None) -> FastAPI:
    setup_logging()
    settings = settings or get_settings()
    store = JobStore(settings)
    pipeline = ConversionPipeline(settings, store)
    signer = get_signer()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        cleanup_task = asyncio.create_task(_cleanup_loop(store, settings))
        try:
            yield
        finally:
            cleanup_task.cancel()
            try:
                await cleanup_task
            except asyncio.CancelledError:
                pass
            store.cleanup_all()

    app = FastAPI(title="Add2Wallet API", version="1.0.0", lifespan=lifespan)
    app.state.settings = settings
    app.state.store = store
    app.state.pipeline = pipeline
    app.state.signer = signer

    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(settings.cors_origins),
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.include_router(create_router())

    @app.exception_handler(ConversionError)
    async def conversion_error_handler(request: Request, exc: ConversionError) -> JSONResponse:
        logger.info(
            "Request failed",
            extra={
                "a2w_error_code": exc.code,
                "a2w_path": request.url.path,
                "a2w_status_code": exc.status_code,
            },
        )
        return JSONResponse(
            status_code=exc.status_code,
            content={
                "error": exc.message,
                "detail": {"code": exc.code, "message": exc.message},
            },
        )

    return app


async def _cleanup_loop(store: JobStore, settings: Settings) -> None:
    while True:
        await asyncio.sleep(settings.cleanup_interval_seconds)
        removed = store.cleanup_expired()
        if removed:
            logger.info("Cleaned up expired jobs", extra={"a2w_removed_jobs": removed})
