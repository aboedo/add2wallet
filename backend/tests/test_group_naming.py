"""A set of passes has to arrive with a name for the set.

The client had no title logic for a group and headed it with its first
member — which on a numbered set is "Coldplay #1", and on an itinerary is the
first leg. Both are the one name guaranteed to be wrong for the whole. The
document-level extraction now answers `group_name`, and a plain derivation
covers the documents the model says nothing about.
"""

import asyncio

from app.core.metadata import _metadata_from_json, _metadata_prompt
from app.core.models import AnalysisResult, ClassifiedDocument, ExtractedDocument, StructuredMetadata
from app.core.pipeline import _derived_group_name, _job_metadata
from app.core.stages import ClassificationStage


def _analysis(group_name=None, **metadata) -> AnalysisResult:
    return AnalysisResult(metadata=StructuredMetadata(**metadata), group_name=group_name)


class TestDerivedName:
    def test_a_single_pass_needs_no_group_name(self):
        """One ticket is its own heading; naming a group of one invents a trip."""
        assert _derived_group_name(StructuredMetadata(event_name="Coldplay"), 1) is None

    def test_the_unnumbered_event_name_heads_the_set(self):
        metadata = StructuredMetadata(event_name="Coldplay at Wembley", title="Coldplay #1")
        assert _derived_group_name(metadata, 4) == "Coldplay at Wembley"

    def test_a_document_type_is_not_a_name(self):
        """"Event Ticket" is what the fallback extractor calls everything."""
        metadata = StructuredMetadata(
            event_name="Event Ticket", title="Digital Pass", venue_name="Estadio Centenario"
        )
        assert _derived_group_name(metadata, 3) == "Estadio Centenario"

    def test_nothing_to_go_on_stays_null(self):
        assert _derived_group_name(StructuredMetadata(title="Digital Pass"), 3) is None


class TestJobMetadata:
    def test_the_model_beats_the_derivation(self):
        data = _job_metadata(_analysis(group_name="Norway in a Nutshell", event_name="Vy"), 5)
        assert data["group_name"] == "Norway in a Nutshell"

    def test_a_multi_pass_job_is_named_even_without_the_model(self):
        """No OpenAI, or a model that answered null: the group still gets a head."""
        data = _job_metadata(_analysis(event_name="Peñarol vs Nacional"), 2)
        assert data["group_name"] == "Peñarol vs Nacional"

    def test_a_single_pass_job_carries_no_group_name(self):
        assert "group_name" not in _job_metadata(_analysis(event_name="Coldplay"), 1)


class TestClassification:
    def test_document_metadata_names_a_set_that_segments_never_saw(self):
        """Segment extraction bails below two pages of text, so a single page
        holding four tickets only ever had the document-level pass."""
        stage = ClassificationStage(_Settings(), _Extractor(group_name="Coldplay at Wembley"))
        classified = _classify(stage)
        assert classified.group_name == "Coldplay at Wembley"

    def test_the_itinerary_name_still_wins(self):
        stage = ClassificationStage(
            _Settings(), _Extractor(group_name="Vy", segments_group_name="Norway in a Nutshell")
        )
        assert _classify(stage).group_name == "Norway in a Nutshell"


class TestPromptContract:
    def test_the_model_is_asked_for_a_group_name(self):
        prompt = _metadata_prompt("tickets.pdf", "Coldplay", [])
        assert "group_name" in prompt

    def test_a_group_name_in_the_answer_is_kept(self):
        metadata = _metadata_from_json('{"title": "Coldplay", "group_name": "Coldplay at Wembley"}', "m")
        assert metadata.group_name == "Coldplay at Wembley"


# --------------------------------------------------------------------------
# Doubles
# --------------------------------------------------------------------------


class _Settings:
    openai_api_key = None
    openai_model = "test-model"


class _Extractor:
    def __init__(self, group_name=None, segments_group_name=None):
        self.group_name = group_name
        self.segments_group_name = segments_group_name

    async def extract_from_text(self, text, filename, barcode_messages):
        return StructuredMetadata(title="Coldplay #1", group_name=self.group_name)

    async def extract_from_vision(self, images, filename, barcode_messages, fallback_text=""):
        return await self.extract_from_text(fallback_text, filename, barcode_messages)

    async def extract_segments(self, pages, filename):
        return [], None, self.segments_group_name


def _classify(stage) -> ClassifiedDocument:
    from app.core.models import DocumentKind, ValidatedUpload

    upload = ValidatedUpload(
        filename="tickets.pdf", content_type="application/pdf", kind=DocumentKind.pdf,
        data=b"%PDF", extension=".pdf",
    )
    extracted = ExtractedDocument(text="Coldplay", page_count=1, pages=["Coldplay"])
    return asyncio.run(stage.run(upload, extracted))
