"""Trip identity and per-leg detail must survive the upload response.

The pipeline has produced `group_id`, `group_name` and per-leg `segment` data
for a long time, but `_sanitize_metadata` filters against an allowlist and none
of the three were on it. The client therefore only ever saw them on
`/tickets/{job_id}` — never on the upload that creates the pass, which is the
one moment it can file the pass into a trip.
"""

import pathlib
import time

import pytest

from app.api.routes import _metadata_for_job, _sanitize_metadata
from app.core.models import StoredJob

SEGMENT = {
    "origin": "Málaga",
    "destination": "Madrid",
    "depart_time": "07:20",
    "arrive_time": "09:50",
    "seat_info": "7A",
    "carrier": "AVLO",
}


def _job(ai_metadata=None, ticket_info=None) -> StoredJob:
    job = StoredJob(
        job_id="j1",
        user_id="u1",
        filename="itinerary.pdf",
        status="completed",
        progress=100,
        created_at=time.time(),
        file_path=pathlib.Path("/tmp/itinerary.pdf"),
    )
    job.ai_metadata = ai_metadata
    job.ticket_info = ticket_info or []
    return job


def _payload(job: StoredJob):
    return _sanitize_metadata(_metadata_for_job(job))


class TestTripFieldsReachTheClient:
    def test_group_identity_is_merged_from_the_job_onto_the_ticket(self):
        """group_id lives on the job, the leg lives on the ticket — the client
        needs both in one payload."""
        job = _job(
            ai_metadata={"title": "Doc", "group_id": "QX7RM2", "group_name": "Summer in Iberia"},
            ticket_info=[{"metadata": {"title": "AVLO 02272", "segment": SEGMENT}}],
        )
        payload = _payload(job)
        assert payload["group_id"] == "QX7RM2"
        assert payload["group_name"] == "Summer in Iberia"
        assert payload["title"] == "AVLO 02272", "per-ticket fields still win"

    def test_per_leg_segment_and_route_survive(self):
        job = _job(
            ai_metadata={"title": "Doc"},
            ticket_info=[{"metadata": {"segment": SEGMENT, "route": "Málaga → Madrid"}}],
        )
        payload = _payload(job)
        assert payload["segment"] == SEGMENT
        assert payload["route"] == "Málaga → Madrid"

    def test_document_level_segments_list_survives(self):
        job = _job(
            ai_metadata={"title": "Doc", "segments": [SEGMENT]},
            ticket_info=[{"metadata": {"title": "Leg 1"}}],
        )
        assert _payload(job)["segments"] == [SEGMENT]

    def test_a_ticket_that_already_has_group_identity_is_not_overwritten(self):
        job = _job(
            ai_metadata={"group_id": "FROM-JOB"},
            ticket_info=[{"metadata": {"group_id": "FROM-TICKET"}}],
        )
        assert _payload(job)["group_id"] == "FROM-TICKET"

    @pytest.mark.parametrize("field", ["group_id", "group_name", "segment", "segments", "route"])
    def test_field_is_on_the_allowlist(self, field):
        from app.api.routes import ENHANCED_METADATA_FIELDS

        assert field in ENHANCED_METADATA_FIELDS


class TestSanitizationStillProtects:
    def test_unknown_fields_are_still_stripped(self):
        job = _job(ticket_info=[{"metadata": {"title": "T", "internal_debug_state": "leak"}}])
        assert "internal_debug_state" not in _payload(job)

    def test_segments_must_be_a_list(self):
        """`segments` is on LIST_FIELDS, so a scalar is nulled rather than passed on."""
        job = _job(ticket_info=[{"metadata": {"title": "T", "segments": "not a list"}}])
        assert _payload(job)["segments"] is None

    def test_no_ticket_info_falls_back_to_document_metadata(self):
        job = _job(ai_metadata={"title": "Doc", "group_id": "QX7RM2"})
        payload = _payload(job)
        assert payload["title"] == "Doc"
        assert payload["group_id"] == "QX7RM2"

    def test_no_metadata_at_all_is_none(self):
        assert _payload(_job()) is None
