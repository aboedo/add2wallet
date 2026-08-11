from __future__ import annotations

import asyncio
import logging
import uuid

from app.core.config import Settings
from app.core.errors import ConversionError
from app.core.models import StoredJob
from app.core.revenuecat import RevenueCatClient
from app.core.stages import (
    ClassificationStage,
    EnrichmentStage,
    ExtractionStage,
    IngestStage,
    PassGenerationStage,
)
from app.core.storage import JobStore


logger = logging.getLogger(__name__)


class ConversionPipeline:
    def __init__(
        self,
        settings: Settings,
        store: JobStore,
        ingest: IngestStage | None = None,
        extraction: ExtractionStage | None = None,
        classification: ClassificationStage | None = None,
        enrichment: EnrichmentStage | None = None,
        generation: PassGenerationStage | None = None,
        revenuecat: RevenueCatClient | None = None,
    ) -> None:
        self.settings = settings
        self.store = store
        self.ingest = ingest or IngestStage(settings)
        self.extraction = extraction or ExtractionStage()
        self.classification = classification or ClassificationStage(settings)
        self.enrichment = enrichment or EnrichmentStage()
        self.generation = generation or PassGenerationStage(settings)
        self.revenuecat = revenuecat or RevenueCatClient(settings)

    async def convert(
        self,
        *,
        filename: str | None,
        content_type: str | None,
        data: bytes,
        user_id: str,
        session_token: str,
        is_retry: bool,
        is_demo: bool,
    ) -> StoredJob:
        if not session_token.strip():
            from app.core.errors import ProcessingError

            raise ProcessingError("Missing session_token")

        upload = await asyncio.to_thread(self.ingest.run, filename, content_type, data)
        job_id = str(uuid.uuid4())
        job = self.store.create_processing_job(job_id, user_id, upload)

        try:
            extracted = await self.extraction.run(upload)
            job.progress = 35
            classified = await self.classification.run(upload, extracted)
            job.progress = 55
            analysis = await asyncio.to_thread(self.enrichment.run, upload, extracted, classified)
            job.progress = 70
            artifacts = await self.generation.run(upload, analysis)
            job.progress = 85
            self.store.save_artifacts(
                job_id,
                artifacts,
                [barcode.model_dump() for barcode in analysis.barcodes],
                _job_metadata(analysis, len(artifacts)),
                analysis.warnings,
            )
            job.progress = 90
            remaining = await asyncio.to_thread(
                self.revenuecat.deduct_pass,
                user_id,
                is_retry,
                is_demo,
                job_id,
            )
            return self.store.complete_job(job_id, remaining)
        except ConversionError as exc:
            self.store.fail_job(job_id, exc.message)
            raise
        except Exception as exc:
            logger.exception("Conversion failed", extra={"a2w_job_id": job_id})
            self.store.fail_job(job_id, str(exc))
            from app.core.errors import ProcessingError

            raise ProcessingError("Could not create an Apple Wallet pass from this file") from exc


def _job_metadata(analysis, pass_count: int = 1) -> dict:
    """Document-level metadata plus the group identity the app needs to tie
    related passes together (a five-leg itinerary is one booking)."""
    data = analysis.metadata.model_dump(exclude_none=True)
    if analysis.group_id:
        data["group_id"] = analysis.group_id
    group_name = analysis.group_name or _derived_group_name(analysis.metadata, pass_count)
    if group_name:
        data["group_name"] = group_name
    if analysis.segments:
        data["segments"] = [s.model_dump(exclude_none=True) for s in analysis.segments]
    return data


# Names that describe the document type rather than the event. Heading a group
# with one of these says nothing the icon does not already say.
GENERIC_TITLES = {"digital pass", "event ticket", "boarding pass", "ticket", "pass"}


def _derived_group_name(metadata, pass_count: int) -> str | None:
    """A heading for a set the model gave no name for.

    Every ticket of a set is titled "<event> #2", so whichever one the client
    picks to speak for the group is wrong by construction. The unnumbered event
    name is the obvious right answer and needs no model to find it — which also
    means a document processed without OpenAI still gets a usable heading.
    """
    if pass_count <= 1:
        return None
    for candidate in (metadata.event_name, metadata.title, metadata.venue_name, metadata.city):
        name = (candidate or "").strip()
        if name and name.lower() not in GENERIC_TITLES:
            return name
    return None
