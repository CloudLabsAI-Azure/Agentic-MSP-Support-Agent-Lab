"""Seed generator checks across many anchors.

Run from the repository root:
    python -m pytest setup/tests -q

Every team environment is seeded at its own provisioning time (--anchor auto), and the
Expected results blocks in the lab guide quote record counts and historical ticket numbers.
These tests prove that everything except the dates is identical for any anchor, and that the
time invariants the exercises rely on hold.
"""
from __future__ import annotations

import base64
import hashlib
import io
import sys
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

SEED_DIR = Path(__file__).resolve().parents[1] / "assets" / "labfiles" / "seed"
sys.path.insert(0, str(SEED_DIR))

import bizhours  # noqa: E402
import generate_seed  # noqa: E402

SEED = 20261001
FIXTURE_ANCHOR = datetime(2026, 10, 7, 14, 0, tzinfo=timezone.utc)
NEW_INCIDENTS = {"TCK-10514", "TCK-10515"}


def anchors() -> list[datetime]:
    """Hourly for two weeks around the reference, then every 61 hours across a year."""
    result = [bizhours.snap_anchor(FIXTURE_ANCHOR - timedelta(days=7) + timedelta(hours=h)) for h in range(0, 24 * 14)]
    start = datetime(2026, 1, 5, 9, 0, tzinfo=timezone.utc)
    result += [bizhours.snap_anchor(start + timedelta(hours=61 * k)) for k in range(0, 150)]
    return sorted(set(result))


def signature(data: dict) -> tuple:
    """Everything that must not depend on the anchor."""
    tickets = tuple(
        (t["_key"]["spk_ticketnumber"], t["_lookups"]["spk_CustomerId"][2],
         (t["_lookups"].get("spk_RelatedArticleId") or [None, None, None])[2],
         (t["_lookups"].get("spk_AssignedTechnicianId") or [None, None, None])[2],
         t["spk_name"], t["spk_priority"], t["spk_category"], t["spk_slatargethours"],
         t["spk_isescalated"], t.get("spk_escalationlevel"), t.get("spk_escalationreason"), t.get("_owner_team"))
        for t in data["tickets"])
    notes = tuple((n["_key"]["spk_notecode"], n["spk_isinternal"], n["spk_body"]) for n in data["ticketnotes"])
    procedures = tuple((p["_key"]["spk_procedurecode"], p["spk_name"], p["spk_details"]) for p in data["customerprocedures"])
    runbooks = tuple((r["_key"]["spk_runbookcode"], r["spk_steps"]) for r in data["runbooks"])
    documents = tuple(hashlib.sha256(a["documentbody"].encode()).hexdigest() for a in data["annotations"])
    incidents = tuple((t["_key"]["spk_ticketnumber"], t["_lookups"]["spk_CustomerId"][2], t["spk_description"])
                      for t in data["newincidents"])
    return tickets, notes, procedures, runbooks, documents, incidents


def parse(ts: str) -> datetime:
    return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


@pytest.fixture(scope="module")
def reference():
    return generate_seed.build(FIXTURE_ANCHOR, SEED)


def test_reference_counts(reference):
    manifest = reference["manifest"]
    counts = manifest["counts"]
    assert counts["tickets"] == 474
    assert counts["ticketnotes"] == 1203
    assert counts["accounts"] == 24 and counts["contacts"] == 72
    assert counts["knowledgearticles"] == 50 and counts["technicians"] == 12
    assert counts["customerprocedures"] == 63 and counts["runbooks"] == 12 and counts["annotations"] == 1
    assert manifest["open_tickets"] == 43 and manifest["open_tickets_after_new_incidents"] == 45
    assert manifest["escalated_tickets"] == 39
    assert manifest["restricted"]["records"] == 71
    assert manifest["searchable_documents"]["total"] == 561


def test_new_incidents_are_outside_the_indexed_tickets(reference):
    indexed = {t["_key"]["spk_ticketnumber"] for t in reference["tickets"]}
    assert NEW_INCIDENTS.isdisjoint(indexed)
    assert {t["_key"]["spk_ticketnumber"] for t in reference["newincidents"]} == NEW_INCIDENTS
    for t in reference["newincidents"]:
        assert t["spk_priority"] is None and t["spk_category"] is None
        assert "spk_AssignedTechnicianId" not in t["_lookups"]


def test_configuration_document_is_a_word_file(reference):
    doc = reference["annotations"][0]
    with zipfile.ZipFile(io.BytesIO(base64.b64decode(doc["documentbody"]))) as zf:
        assert "Woodgrove Bank" in zf.read("word/document.xml").decode("utf-8")
        assert "docProps/custom.xml" in zf.namelist()


@pytest.mark.parametrize("anchor", anchors(), ids=lambda a: a.strftime("%Y%m%dT%H"))
def test_anchor_invariance(reference, anchor):
    data = generate_seed.build(anchor, SEED)
    assert signature(data) == signature(reference)

    open_numbers = {t["number"] for t in generate_seed.OPEN_TICKETS} | {generate_seed.INCOMPLETE_TICKET["number"]}
    history = [t for t in data["tickets"] if t["_key"]["spk_ticketnumber"] not in open_numbers]
    opened_open = [parse(t["spk_openedon"]) for t in data["tickets"] if t["_key"]["spk_ticketnumber"] in open_numbers]
    oldest_open = min(opened_open)
    assert max(parse(t["spk_openedon"]) for t in history) < oldest_open
    assert max(parse(t["spk_resolvedon"]) for t in history) <= anchor - timedelta(hours=4)
    assert max(parse(n["spk_notedon"]) for n in data["ticketnotes"]) <= anchor
    # The new incidents are the newest tickets and never open after the snapshot.
    newest_seeded = max(opened_open)
    for t in data["newincidents"]:
        assert newest_seeded < parse(t["spk_openedon"]) <= anchor
    # Historical numbers stay in opening order.
    ordered = sorted(history, key=lambda t: t["_key"]["spk_ticketnumber"])
    assert [t["spk_openedon"] for t in ordered] == sorted(t["spk_openedon"] for t in ordered)
