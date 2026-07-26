import pytest

from app.core.config import Settings
from app.core.errors import ProcessingError
from app.core.models import AnalysisResult, DocumentKind, PassArtifact, StructuredMetadata, ValidatedUpload
from app.core.pipeline import ConversionPipeline
from app.core.storage import JobStore
from app.services.v2.pass_signer import PassSigner


def _settings(tmp_path):
    return Settings(
        api_key="development-api-key",
        max_upload_bytes=10 * 1024 * 1024,
        upload_dir=tmp_path / "uploads",
        job_ttl_seconds=1800,
        cleanup_interval_seconds=300,
        openai_api_key=None,
        openai_model="gpt-4o-mini",
        revenuecat_secret_key=None,
        revenuecat_project_id="project",
        pass_type_identifier="pass.com.example.test",
        team_identifier="TEAM12345",
        app_store_id=None,
        cors_origins=("*",),
    )


def test_failed_jobs_remove_temporary_upload(tmp_path):
    store = JobStore(_settings(tmp_path))
    upload = ValidatedUpload(
        filename="ticket.pdf",
        content_type="application/pdf",
        kind=DocumentKind.pdf,
        data=b"%PDF-",
        extension="pdf",
    )
    job = store.create_processing_job("job-id", "user-id", upload)

    assert job.file_path.exists()

    store.fail_job("job-id", "failed")

    assert store.get("job-id").status == "failed"
    assert not job.file_path.exists()


def test_failed_jobs_remove_saved_passes(tmp_path):
    store = JobStore(_settings(tmp_path))
    upload = ValidatedUpload(
        filename="ticket.pdf",
        content_type="application/pdf",
        kind=DocumentKind.pdf,
        data=b"%PDF-",
        extension="pdf",
    )
    store.create_processing_job("job-id", "user-id", upload)
    store.save_artifacts(
        "job-id",
        [],
        [],
        {},
        [],
    )
    pass_path = tmp_path / "uploads" / "job-id.pkpass"
    pass_path.write_bytes(b"pkpass")
    store.get("job-id").pass_paths = [pass_path]

    store.fail_job("job-id", "failed")

    assert not pass_path.exists()


def test_signing_failure_does_not_emit_unsigned_pass(tmp_path, monkeypatch):
    pass_dir = tmp_path / "pass"
    pass_dir.mkdir()
    (pass_dir / "pass.json").write_text('{"formatVersion":1}')

    signer = PassSigner(certificates_path=str(tmp_path))
    signer.signing_enabled = True
    monkeypatch.setattr(signer, "sign_manifest", lambda manifest_path: b"")

    with pytest.raises(ProcessingError, match="Pass signing failed"):
        signer.package_pass(str(pass_dir))


@pytest.mark.asyncio
async def test_revenuecat_is_not_called_if_pass_persistence_fails(tmp_path, monkeypatch):
    class FailingStore(JobStore):
        def save_artifacts(self, *args, **kwargs):
            raise OSError("disk full")

    class StubIngest:
        def run(self, filename, content_type, data):
            return ValidatedUpload(
                filename=filename,
                content_type=content_type,
                kind=DocumentKind.pdf,
                data=data,
                extension="pdf",
            )

    class StubExtraction:
        async def run(self, upload):
            from app.core.models import ExtractedDocument

            return ExtractedDocument(text="ticket", page_count=1)

    class StubClassification:
        async def run(self, upload, extracted):
            from app.core.models import ClassifiedDocument

            return ClassifiedDocument(metadata=StructuredMetadata(title="Ticket"))

    class StubEnrichment:
        def run(self, upload, extracted, classified):
            return AnalysisResult(text="ticket", metadata=classified.metadata)

    class StubGeneration:
        async def run(self, upload, analysis):
            return [
                PassArtifact(
                    ticket_number=1,
                    title="Ticket",
                    description="Ticket",
                    metadata=analysis.metadata.model_dump(exclude_none=True),
                    data=b"pkpass",
                )
            ]

    class StubRevenueCat:
        called = False

        def deduct_pass(self, *args):
            self.called = True
            return 1

    revenuecat = StubRevenueCat()
    store = FailingStore(_settings(tmp_path))
    pipeline = ConversionPipeline(
        _settings(tmp_path),
        store,
        ingest=StubIngest(),
        extraction=StubExtraction(),
        classification=StubClassification(),
        enrichment=StubEnrichment(),
        generation=StubGeneration(),
        revenuecat=revenuecat,
    )
    monkeypatch.setattr("app.core.pipeline.uuid.uuid4", lambda: "job-id")

    with pytest.raises(ProcessingError, match="Could not create an Apple Wallet pass"):
        await pipeline.convert(
            filename="ticket.pdf",
            content_type="application/pdf",
            data=b"%PDF-",
            user_id="user-id",
            session_token="token",
            is_retry=False,
            is_demo=False,
        )

    assert revenuecat.called is False
