"""Seed generator checks across many anchors.

Run from the repository root:
    python -m pytest setup/tests -q

Every team environment is seeded at its own provisioning time (--anchor auto), and the lab
guide and the facilitator answer keys quote record counts and historical ticket numbers. These
tests prove that everything except the dates is identical for any anchor, and that the time
invariants the exercises rely on hold.
"""
from __future__ import annotations

import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

SEED_DIR = Path(__file__).resolve().parents[1] / "assets" / "labfiles" / "seed"
sys.path.insert(0, str(SEED_DIR))

import bizhours  # noqa: E402
import generate_seed  # noqa: E402

SEED = 20261001
FIXTURE_ANCHOR = datetime(2026, 10, 7, 14, 0, tzinfo=timezone.utc)


def anchors() -> list[datetime]:
    """Hourly for two weeks around the reference, then every 61 hours across a year."""
    result = [bizhours.snap_anchor(FIXTURE_ANCHOR - timedelta(days=7) + timedelta(hours=h)) for h in range(0, 24 * 14)]
    start = datetime(2026, 1, 5, 9, 0, tzinfo=timezone.utc)
    result += [bizhours.snap_anchor(start + timedelta(hours=61 * k)) for k in range(0, 150)]
    return sorted(set(result))


def signature(data: dict) -> tuple:
    """Everything that must not depend on the anchor."""
    tickets = tuple(
        (t["_key"]["msp_ticketnumber"], t["_lookups"]["msp_CustomerId"][2],
         (t["_lookups"].get("msp_RelatedArticleId") or [None, None, None])[2],
         t["msp_name"], t["msp_priority"], t["msp_category"], t["msp_slatargethours"])
        for t in data["tickets"])
    notes = tuple((n["_key"]["msp_notecode"], n["msp_isinternal"], n["msp_body"]) for n in data["ticketnotes"])
    return tickets, notes


def parse(ts: str) -> datetime:
    return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


@pytest.fixture(scope="module")
def reference():
    return generate_seed.build(FIXTURE_ANCHOR, SEED)


def test_reference_counts(reference):
    counts = reference["manifest"]["counts"]
    assert counts["tickets"] == 473
    assert counts["ticketnotes"] == 1161
    assert counts["accounts"] == 24 and counts["contacts"] == 72
    assert counts["knowledgearticles"] == 50 and counts["technicians"] == 12
    assert reference["manifest"]["open_tickets"] == 42
    assert reference["manifest"]["searchable_documents"]["total"] == 548


@pytest.mark.parametrize("anchor", anchors(), ids=lambda a: a.strftime("%Y%m%dT%H"))
def test_anchor_invariance(reference, anchor):
    data = generate_seed.build(anchor, SEED)
    assert signature(data) == signature(reference)

    open_numbers = {t["number"] for t in generate_seed.OPEN_TICKETS}
    history = [t for t in data["tickets"] if t["_key"]["msp_ticketnumber"] not in open_numbers]
    opened_open = [parse(t["msp_openedon"]) for t in data["tickets"] if t["_key"]["msp_ticketnumber"] in open_numbers]
    oldest_open = min(opened_open)
    assert max(parse(t["msp_openedon"]) for t in history) < oldest_open
    assert max(parse(t["msp_resolvedon"]) for t in history) <= anchor - timedelta(hours=4)
    assert max(parse(n["msp_notedon"]) for n in data["ticketnotes"]) <= anchor
    # Historical numbers stay in opening order.
    ordered = sorted(history, key=lambda t: t["_key"]["msp_ticketnumber"])
    assert [t["msp_openedon"] for t in ordered] == sorted(t["msp_openedon"] for t in ordered)
