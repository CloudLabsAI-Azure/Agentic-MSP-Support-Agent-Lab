"""Seed generator checks: exact counts, every scenario the guides use, and determinism.

Run from the repository root:
    python -m pytest setup/tests -q

Every environment is seeded at its own provisioning time (--anchor auto), and the guides
quote record counts, ticket numbers and SLA figures. These tests prove that everything except
the dates is identical for any anchor across a year, that two runs with the same anchor write
byte-identical files, and that each scenario invariant holds. Ticket numbers are never
hard-coded here: they come from the manifest, as they must in the guides.
"""
from __future__ import annotations

import base64
import hashlib
import io
import json
import re
import sys
import zipfile
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

SETUP_DIR = Path(__file__).resolve().parents[1]
SEED_DIR = SETUP_DIR / "assets" / "labfiles" / "seed"
SCHEMA_PATH = SETUP_DIR / "assets" / "labfiles" / "provision" / "dataverse" / "schema.json"
sys.path.insert(0, str(SEED_DIR))

import bizhours  # noqa: E402
import catalog  # noqa: E402
import generate_seed  # noqa: E402
import operations  # noqa: E402

SEED = 20261001
FIXTURE_ANCHOR = datetime(2026, 10, 7, 14, 0, tzinfo=timezone.utc)
OPEN = {catalog.CHOICES["spk_ticketstatus"][s] for s in ("New", "In Progress", "Waiting on Customer")}
CLOSED = {catalog.CHOICES["spk_ticketstatus"][s] for s in ("Resolved", "Closed")}
LABEL = {table: {v: k for k, v in values.items()} for table, values in catalog.CHOICES.items()}
# The 50 lab version 2 articles must keep their published text (only related articles,
# subcategory and tags were added, and British spellings changed to US spellings on
# 2026-11-10: tunneling, license, behavior). SHA-256 of their fields as published in version 3.
ORIGINAL_ARTICLES_SHA256 = "cab10891b3abae06c68f835ce57d7ca286a4804db93880f40b97aefc925e471a"
ARTICLE_FIELDS = ("number", "title", "category", "product", "versions", "tiers", "contracts", "status",
                  "reviewed_days_ago", "symptom", "cause", "resolution", "keywords")
# Characters the lab text must never contain, built without writing them.
FORBIDDEN = (chr(0x2014), chr(0x2013), " " + "-" * 2 + " ")


def anchors() -> list[datetime]:
    """Hourly for two weeks around the reference, then every 61 hours across a year."""
    result = [bizhours.snap_anchor(FIXTURE_ANCHOR - timedelta(days=7) + timedelta(hours=h)) for h in range(0, 24 * 14)]
    start = datetime(2026, 1, 5, 9, 0, tzinfo=timezone.utc)
    result += [bizhours.snap_anchor(start + timedelta(hours=61 * k)) for k in range(0, 150)]
    return sorted(set(result))


def parse(ts: str) -> datetime:
    return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def number(t: dict) -> str:
    return t["_key"]["spk_ticketnumber"]


def kb_of(t: dict) -> str | None:
    return (t["_lookups"].get("spk_RelatedArticleId") or [None, None, None])[2]


def tech_of(t: dict) -> str | None:
    return (t["_lookups"].get("spk_AssignedTechnicianId") or [None, None, None])[2]


def customer_of(t: dict) -> str:
    return t["_lookups"]["spk_CustomerId"][2]


def signature(data: dict) -> tuple:
    """Everything that must not depend on the anchor."""
    tickets = tuple(
        (number(t), customer_of(t), kb_of(t), tech_of(t), t["spk_name"], t["spk_description"], t["spk_priority"],
         t["spk_category"], t["spk_subcategory"], t["spk_outcome"], t["spk_tags"], t["spk_slatargethours"],
         t["spk_slaelapsedhours"], t["spk_slaremaininghours"], t["spk_resolutionsummary"], t["spk_isescalated"],
         t.get("spk_escalationlevel"), t.get("spk_escalationreason"), t.get("_owner_team"))
        for t in data["tickets"])
    notes = tuple((n["_key"]["spk_notecode"], n["spk_isinternal"], n["spk_author"], n["spk_body"]) for n in data["ticketnotes"])
    procedures = tuple((p["_key"]["spk_procedurecode"], p["spk_name"], p["spk_details"]) for p in data["customerprocedures"])
    documents = tuple((d["_key"]["spk_documentcode"], d["spk_name"], d["spk_body"], d["spk_version"])
                      for d in data["customerdocuments"])
    articles = tuple((a["_key"]["spk_articlenumber"], a["spk_name"], a["spk_resolution"], a["spk_relatedarticles"])
                     for a in data["knowledgearticles"])
    runbooks = tuple((r["_key"]["spk_runbookcode"], r["spk_steps"]) for r in data["runbooks"])
    annotations = tuple(hashlib.sha256(a["documentbody"].encode()).hexdigest() for a in data["annotations"])
    incidents = tuple((number(t), customer_of(t), t["spk_description"]) for t in data["newincidents"])
    manifest = {k: v for k, v in data["manifest"].items() if k not in ("anchor", "generated_at")}
    return (tickets, notes, procedures, documents, articles, runbooks, annotations, incidents,
            json.dumps(manifest, sort_keys=True))


@pytest.fixture(scope="module")
def reference():
    return generate_seed.build(FIXTURE_ANCHOR, SEED)


@pytest.fixture(scope="module")
def manifest(reference):
    return reference["manifest"]


@pytest.fixture(scope="module")
def roles(manifest):
    return manifest["role_keys"]


@pytest.fixture(scope="module")
def by_number(reference):
    return {number(t): t for t in reference["tickets"] + reference["newincidents"]}


# =============================================================================== volumes

def test_reference_counts(reference, manifest):
    counts = manifest["counts"]
    assert counts == {
        "businesscalendars": 1, "slapolicies": 16, "technicians": 15, "accounts": 24, "contacts": 72,
        "customerprocedures": 63, "customerdocuments": 36, "runbooks": 12, "knowledgearticles": 120,
        "tickets": 560, "ticketnotes": 1436, "annotations": 1,
    }
    assert manifest["historical_tickets"] == 500 and manifest["open_tickets"] == 60
    assert len(manifest["new_incidents"]) == 2 and manifest["open_tickets_after_new_incidents"] == 62
    assert sum(1 for t in reference["tickets"] if t["spk_status"] in CLOSED) == 500
    assert sum(1 for t in reference["tickets"] if t["spk_status"] in OPEN) == 60
    assert counts["ticketnotes"] >= 800
    notes = reference["ticketnotes"]
    assert {True, False} == {n["spk_isinternal"] for n in notes}
    assert manifest["searchable_documents"] == {
        "knowledge_articles": 120, "customer_documents": 36, "runbooks": 12, "tickets": 560, "customers": 24,
        "sla_snapshot": 1, "total": 753}
    assert manifest["restricted"]["records"] == manifest["scenarios"]["restricted_records"]["records"] == 96


def test_numbering_is_continuous_and_chronological(reference, manifest, roles):
    history = sorted((t for t in reference["tickets"] if t["spk_status"] in CLOSED), key=number)
    open_ = sorted((t for t in reference["tickets"] if t["spk_status"] in OPEN), key=number)
    assert [number(t) for t in history] == [f"TCK-{n}" for n in range(10001, 10501)]
    assert [number(t) for t in open_] == [f"TCK-{n}" for n in range(10501, 10561)]
    assert manifest["new_incidents"] == ["TCK-10561", "TCK-10562"]
    assert manifest["numbering"] == {"historical": ["TCK-10001", "TCK-10500"], "open": ["TCK-10501", "TCK-10560"],
                                     "new_incidents": ["TCK-10561", "TCK-10562"]}
    for group in (history, open_, reference["newincidents"]):
        opened = [t["spk_openedon"] for t in sorted(group, key=number)]
        assert opened == sorted(opened)
    assert max(parse(t["spk_openedon"]) for t in history) < min(parse(t["spk_openedon"]) for t in open_)
    authored = {t["role"] for t in generate_seed.OPEN_TICKETS} | {operations.INCOMPLETE_TICKET["role"]}
    incidents = {t["role"] for t in operations.NEW_INCIDENTS}
    assert set(roles) == authored | incidents and len(roles) == 62
    assert sorted(roles.values()) == [f"TCK-{n}" for n in range(10501, 10563)]
    assert roles["new_incident_adatum"] == "TCK-10561" and roles["new_incident_consolidated"] == "TCK-10562"


def test_new_incidents_are_outside_the_export(reference, manifest):
    indexed = {number(t) for t in reference["tickets"]}
    new = {number(t) for t in reference["newincidents"]}
    assert new == set(manifest["new_incidents"]) and new.isdisjoint(indexed)
    assert manifest["searchable_documents"]["tickets"] == len(indexed) == 560
    for t in reference["newincidents"]:
        assert t["spk_priority"] is None and t["spk_category"] is None and t["spk_subcategory"] is None
        assert t["spk_slatargethours"] is None and t["spk_outcome"] is None and t["spk_tags"] is None
        assert "spk_AssignedTechnicianId" not in t["_lookups"] and "spk_RelatedArticleId" not in t["_lookups"]
        assert LABEL["spk_ticketstatus"][t["spk_status"]] == "New"
    assert [customer_of(t) for t in sorted(reference["newincidents"], key=number)] == ["CUST-019", "CUST-020"]


# =============================================================================== SLA

def test_sla_arithmetic(reference, manifest):
    anchor = parse(manifest["anchor"])
    for t in reference["tickets"]:
        if t["spk_slatargethours"] is None:
            assert t["spk_priority"] is None and t["spk_status"] in OPEN
            continue
        cust = next(c for c in catalog.CUSTOMERS if c["code"] == customer_of(t))
        prio = int(LABEL["spk_priority"][t["spk_priority"]][1])
        target = float(catalog.SLA_RESOLUTION_HOURS[cust["tier"]][prio])
        opened = parse(t["spk_openedon"])
        end = parse(t["spk_resolvedon"]) if t["spk_status"] in CLOSED else anchor
        assert t["spk_slatargethours"] == target
        assert t["spk_slaelapsedhours"] == bizhours.business_hours_between(opened, end)
        assert t["spk_slaremaininghours"] == round(target - t["spk_slaelapsedhours"], 2)
        assert parse(t["spk_sladueon"]) == bizhours.add_business_hours(opened, target)
        assert parse(t["spk_slacalculatedon"]) == end
        expected = bizhours.sla_status(target, t["spk_slaelapsedhours"], resolved=t["spk_status"] in CLOSED)
        assert LABEL["spk_slastatus"][t["spk_slastatus"]] == expected


def test_sla_set(reference, manifest, roles):
    sla = manifest["scenarios"]["sla_set"]
    near = [(r["role"], r["remaining_hours"]) for r in sla["near_breach"]]
    breached = [(r["role"], r["remaining_hours"]) for r in sla["breached"]]
    assert near == [("contoso_lab_network", 0.5), ("humongous_claims_certificate", 1.0), ("bellows_print_queue", 2.0)]
    assert breached == [("tailspin_store_receipts", -6.0), ("northwind_tunnel_down", -1.5)]
    special = {r for r, _ in near + breached}
    for t in reference["tickets"]:
        if t["spk_status"] in OPEN and t["spk_slaremaininghours"] is not None and number(t) not in {roles[r] for r in special}:
            assert t["spk_slaremaininghours"] >= 6.0
    first_five = [roles[r] for r in ("tailspin_store_receipts", "northwind_tunnel_down", "contoso_lab_network",
                                     "humongous_claims_certificate", "bellows_print_queue")]
    assert sla["first_five_by_remaining"] == first_five
    assert sla["lowest_remaining_of_the_others"] >= 6.0


# =============================================================================== knowledge

def test_knowledge_articles():
    articles = catalog.KB_ARTICLES
    assert len(articles) == 120 and len({a["number"] for a in articles}) == 120
    assert all(re.fullmatch(r"KB0(0\d\d|1[0-9]\d)", a["number"]) for a in articles)
    assert Counter(a["status"] for a in articles) == {"Published": 117, "Draft": 2, "Retired": 1}
    assert [a["number"] for a in articles if a["status"] == "Retired"] == ["KB0019"]
    original = articles[:50]
    blob = json.dumps([{f: a[f] for f in ARTICLE_FIELDS} for a in original], sort_keys=True)
    assert hashlib.sha256(blob.encode()).hexdigest() == ORIGINAL_ARTICLES_SHA256
    for a in articles:
        assert a["subcategory"] in catalog.SUBCATEGORIES[a["category"]]
        assert 2 <= len(a["tags"]) <= 3 and all(tag == tag.lower() for tag in a["tags"])


def test_related_articles(reference):
    by = catalog.KB_BY_NUMBER
    asymmetric = 0
    for a in catalog.KB_ARTICLES:
        rel = a["related"]
        assert 2 <= len(rel) <= 4 and len(set(rel)) == len(rel) and a["number"] not in rel
        for r in rel:
            assert by[r]["status"] == "Published", f"{a['number']} points at {r} ({by[r]['status']})"
            asymmetric += a["number"] not in by[r]["related"]
    # Symmetric where sensible: one-way links only from the Retired and Draft articles and
    # a few hubs that are already at four related articles.
    assert asymmetric <= 8
    published = {k["_key"]["spk_articlenumber"]: k["spk_relatedarticles"] for k in reference["knowledgearticles"]}
    assert all(value == ", ".join(by[n]["related"]) for n, value in published.items())


def test_conflicting_pairs(manifest, roles):
    pairs = {tuple(p["articles"]): p for p in manifest["scenarios"]["conflicting_pairs"]["pairs"]}
    assert set(pairs) == {("KB0031", "KB0058"), ("KB0012", "KB0013"), ("KB0044", "KB0045"), ("KB0067", "KB0062")}
    by = catalog.KB_BY_NUMBER
    assert by["KB0012"]["tiers"] == ["Platinum", "Gold"] and by["KB0013"]["tiers"] == ["Silver", "Bronze"]
    assert by["KB0044"]["contracts"] == ["Fully Managed", "Co-Managed"] and by["KB0045"]["contracts"] == ["Break-Fix"]
    assert by["KB0067"]["symptom"] == by["KB0062"]["symptom"]
    customers = {c["code"]: c for c in catalog.CUSTOMERS}
    assert customers["CUST-007"]["rea"] == "7.4.0" and customers["CUST-015"]["rea"].startswith("7.3")
    assert customers["CUST-007"]["rra"].startswith("4.") and customers["CUST-007"]["rsg"].startswith("10.1")
    assert customers["CUST-019"]["rra"].startswith("3.")
    # Clean pairs: no customer is covered by both articles of a version or contract split.
    for a, b in (("KB0031", "KB0058"), ("KB0067", "KB0062"), ("KB0044", "KB0045"), ("KB0012", "KB0013")):
        assert not any(generate_seed.eligible(c, by[a]) and generate_seed.eligible(c, by[b]) for c in catalog.CUSTOMERS)


# =============================================================================== technicians

def test_technicians_and_teams(reference):
    assert len(catalog.TECHNICIANS) == 15
    assert catalog.TEAMS == {
        "Service Desk": ["TECH-03", "TECH-06", "TECH-09"],
        "Infrastructure": ["TECH-01", "TECH-02", "TECH-08", "TECH-11", "TECH-14"],
        "Workplace": ["TECH-04", "TECH-10", "TECH-12", "TECH-15"],
        "Security and Identity": ["TECH-05", "TECH-07", "TECH-13"],
    }
    team_of = {t["code"]: t["team"] for t in catalog.TECHNICIANS}
    assert all(team_of[c] == team for team, codes in catalog.TEAMS.items() for c in codes)
    assert set(catalog.CHOICES["spk_technicianteam"]) == set(catalog.TEAMS)
    for category, codes in catalog.CATEGORY_TEAMS.items():
        assert all(team_of[c] in catalog.CATEGORY_OWNERS[category] for c in codes)
    for category, codes in catalog.LEGACY_CATEGORY_TEAMS.items():
        assert all(team_of[c] in catalog.CATEGORY_OWNERS[category] for c in codes)
    rows = {t["_key"]["spk_techniciancode"]: t for t in reference["technicians"]}
    assert rows["TECH-02"]["spk_isavailable"] is False and "leave" in rows["TECH-02"]["spk_availabilitynote"]
    assert all(r["spk_availabilitynote"] for r in rows.values())
    assert all(r["spk_email"].endswith("@relecloud.example") for r in rows.values())
    assert sum(1 for t in catalog.TECHNICIANS if not t["available"]) == 1


# =============================================================================== tickets

def test_subcategory_outcome_and_tags(reference):
    for t in reference["tickets"]:
        if t["spk_category"] is None:
            assert t["spk_subcategory"] is None and t["spk_tags"] is None
            continue
        sub = LABEL["spk_subcategory"][t["spk_subcategory"]]
        assert catalog.SUBCATEGORY_CATEGORY[sub] == LABEL["spk_category"][t["spk_category"]]
        if kb_of(t):
            assert sub == catalog.KB_BY_NUMBER[kb_of(t)]["subcategory"]
        tags = t["spk_tags"].split(", ")
        assert 2 <= len(tags) <= 5 and all(tag == tag.lower() and tag for tag in tags)
        if t["spk_status"] in CLOSED:
            assert t["spk_outcome"] in LABEL["spk_outcome"]
        else:
            assert t["spk_outcome"] is None and t["spk_resolvedon"] is None
    outcomes = Counter(LABEL["spk_outcome"][t["spk_outcome"]] for t in reference["tickets"] if t["spk_status"] in CLOSED)
    assert set(outcomes) == set(catalog.CHOICES["spk_outcome"])
    for t in reference["tickets"]:
        if t["spk_outcome"] == catalog.CHOICES["spk_outcome"]["Duplicate"]:
            master = re.search(r"TCK-\d{5}", t["spk_resolutionsummary"]).group(0)
            assert master < number(t) and kb_of(t) is None


def test_history_patterns(reference):
    history = [t for t in reference["tickets"] if t["spk_status"] in CLOSED]

    def rows(kb):
        return [t for t in history if kb_of(t) == kb]
    kb0023 = rows("KB0023")
    assert len(kb0023) == 10
    assert {LABEL["spk_priority"][t["spk_priority"]] for t in kb0023} == {"P3 Medium"}
    assert {tech_of(t) for t in kb0023} == {"TECH-01"}
    assert {LABEL["spk_escalationlevel"][t["spk_escalationlevel"]] for t in kb0023} == {"Account Manager"}
    kb0133 = rows("KB0133")
    p2 = [t for t in kb0133 if t["spk_priority"] == catalog.CHOICES["spk_priority"]["P2 High"]]
    assert len(kb0133) == 10 and {tech_of(t) for t in kb0133} == {"TECH-06"} and len(p2) == 7
    assert {LABEL["spk_escalationlevel"][t["spk_escalationlevel"]] for t in p2} == {"Vendor"}
    assert not any(t["spk_isescalated"] for t in kb0133 if t not in p2)
    routing = [t for t in kb0133 if "routing application" in t["spk_name"].lower()]
    assert len(routing) == 2 and all(t in p2 for t in routing)
    for kb, count in {"KB0058": 8, "KB0028": 5, "KB0067": 5, "KB0047": 4}.items():
        assert len(rows(kb)) == count
    for kb, code in operations.TECHNICIAN_BY_ARTICLE.items():
        assert rows(kb) and {tech_of(t) for t in rows(kb)} == {code}


def test_escalation_patterns(reference, manifest):
    history = [t for t in reference["tickets"] if t["spk_status"] in CLOSED]
    escalated = [t for t in history if t["spk_isescalated"]]
    assert 40 <= len(escalated) <= 55
    levels = Counter(LABEL["spk_escalationlevel"][t["spk_escalationlevel"]] for t in escalated)
    assert set(levels) == set(catalog.CHOICES["spk_escalationlevel"]) and min(levels.values()) >= 8
    assert manifest["scenarios"]["escalation_patterns"]["history_total"] == len(escalated)
    for t in history:
        if t["spk_priority"] == catalog.CHOICES["spk_priority"]["P1 Critical"]:
            assert LABEL["spk_escalationlevel"][t["spk_escalationlevel"]] == "Major Incident"
    open_levels = {e["level"] for e in manifest["scenarios"]["escalation_patterns"]["open_escalated"]}
    assert open_levels == set(catalog.CHOICES["spk_escalationlevel"])


def test_woodgrove_and_recurring(reference, manifest, roles):
    open_by_customer = Counter(customer_of(t) for t in reference["tickets"] if t["spk_status"] in OPEN)
    assert open_by_customer["CUST-007"] == 6
    assert max(v for k, v in open_by_customer.items() if k != "CUST-007") < 6
    recurring = {i["customer_code"]: i for i in manifest["scenarios"]["recurring_issues"]["issues"]}
    assert set(recurring) == {"CUST-007", "CUST-012", "CUST-006"}
    assert all(i["occurrences"] >= 3 for i in recurring.values())
    for code, kb in (("CUST-012", "KB0059"), ("CUST-006", "KB0130")):
        for n in recurring[code]["history"]:
            t = next(x for x in reference["tickets"] if number(x) == n)
            assert customer_of(t) == code and kb_of(t) == kb


def test_untriaged_and_incomplete(reference, manifest, roles):
    untriaged = [t for t in reference["tickets"] + reference["newincidents"]
                 if t["spk_status"] == catalog.CHOICES["spk_ticketstatus"]["New"] and t["spk_priority"] is None]
    assert len(untriaged) == 5 == manifest["scenarios"]["untriaged"]["view_count_after_new_incidents"]
    incomplete = manifest["scenarios"]["incomplete_tickets"]["tickets"]
    assert len(incomplete) >= 2 and all(i["missing"] for i in incomplete)
    assert {i["role"] for i in incomplete} == {"incomplete_vanarsdel", "incomplete_wingtip_email"}


def test_new_incident_expected_results(manifest, roles):
    s = manifest["scenarios"]
    adatum = s["new_incident_adatum_expected"]
    assert adatum["true_matches"]["history"] == [t["ticket"] for t in s["kb0023_history"]["tickets"]]
    assert adatum["true_matches"]["open"]["ticket"] == roles["trey_vault_quota"]
    assert set(adatum["decoys"]) >= {"KB0012", "KB0013", "KB0033", "KB0036", "KB0039"}
    assert adatum["recommendation"]["sla_target_hours"] == 32 and adatum["recommendation"]["technician"]["code"] == "TECH-01"
    consolidated = s["new_incident_consolidated_expected"]
    assert consolidated["recommendation"]["sla_target_hours"] == 16
    assert {r["role"] for r in consolidated["similar_symptom_different_incident"]} == {
        "untriaged_lucerne_cert", "humongous_claims_certificate"}


# =============================================================================== customers and documents

def test_customer_fields(reference):
    for a in reference["accounts"]:
        assert a["spk_servicesinscope"] and a["spk_configurationnotes"]
        sentences = [s for s in re.split(r"(?<=[.])\s+", a["spk_configurationnotes"]) if s]
        assert 2 <= len(sentences) <= 4, a["_key"]
    assert len(reference["accounts"]) == 24 and len(reference["contacts"]) == 72


def test_customer_documents(reference):
    docs = reference["customerdocuments"]
    assert [d["_key"]["spk_documentcode"] for d in docs] == [f"CDOC-{n:03d}" for n in range(1, 37)]
    types = Counter(LABEL["spk_documenttype"][d["spk_documenttype"]] for d in docs)
    assert types == {"Support policy": 24, "Escalation procedure": 6, "Configuration notes": 6}
    policies = {d["_lookups"]["spk_CustomerId"][2] for d in docs if d["spk_documenttype"] == 765401501}
    assert policies == {c["code"] for c in catalog.CUSTOMERS}
    escalation = {d["_lookups"]["spk_CustomerId"][2] for d in docs if d["spk_documenttype"] == 765401502}
    assert escalation == {"CUST-007", "CUST-013", "CUST-001", "CUST-021", "CUST-014", "CUST-020"}
    config = {d["_lookups"]["spk_CustomerId"][2] for d in docs if d["spk_documenttype"] == 765401503}
    assert config == {"CUST-007", "CUST-020", "CUST-019", "CUST-013", "CUST-002", "CUST-008"}
    contact_values = {c["emailaddress1"] for c in reference["contacts"]} | {c["telephone1"] for c in reference["contacts"]} \
        | {c["mobilephone"] for c in reference["contacts"]}
    docx = operations.CONFIG_DOCUMENT["paragraphs"]
    for d in docs:
        body = d["spk_body"]
        assert 1500 <= len(body) <= 4000, d["_key"]
        assert not any(v in body for v in contact_values)
        for ip in re.findall(r"\b\d{1,3}(?:\.\d{1,3}){3}\b", body):
            assert ip.startswith(("192.0.2.", "198.51.100.", "203.0.113."))
        assert bool(d.get("_owner_team")) == (d["_lookups"]["spk_CustomerId"][2] == "CUST-014")
        assert re.fullmatch(r"\d+\.\d+", d["spk_version"])
    woodgrove = next(d["spk_body"] for d in docs if d["spk_name"].startswith("Configuration notes: Woodgrove"))
    assert operations.CONFIG_DOCUMENT["filename"] in woodgrove
    for secret in ("203.0.113", "198.51.100", "192.0.2", "28800", "WGB-STAFF"):
        assert secret not in woodgrove and any(secret in p for p in docx)


def test_configuration_document_is_a_word_file(reference):
    doc = reference["annotations"][0]
    with zipfile.ZipFile(io.BytesIO(base64.b64decode(doc["documentbody"]))) as zf:
        assert "Woodgrove Bank" in zf.read("word/document.xml").decode("utf-8")
        assert "docProps/custom.xml" in zf.namelist()


# =============================================================================== data protection

def _luhn(digits: str) -> bool:
    total = 0
    for i, ch in enumerate(reversed(digits)):
        d = int(ch)
        if i % 2:
            d = d * 2 - 9 if d > 4 else d * 2
        total += d
    return total % 10 == 0


def test_card_number_notes(reference, manifest, roles):
    assert _luhn(operations.CARD_NUMBER)
    found = []
    for n in reference["ticketnotes"]:
        for match in re.finditer(r"\b\d(?:[ -]?\d){12,18}\b", n["spk_body"]):
            digits = re.sub(r"\D", "", match.group(0))
            if len(digits) == 16 and _luhn(digits):
                assert digits == operations.CARD_NUMBER
                found.append(n)
    assert len(found) == 4
    for n in found:
        assert n["spk_isinternal"] and "card number" in n["spk_body"]
        assert re.search(r"\bexp \d{2}/\d{2}\b", n["spk_body"])
    published = {c["note"] for c in manifest["scenarios"]["card_number_tickets"]["notes"]}
    assert published == {n["_key"]["spk_notecode"] for n in found}
    tickets = {c["ticket"] for c in manifest["scenarios"]["card_number_tickets"]["notes"]}
    assert {roles["trey_vault_quota"], roles["margies_firewall_quote"]} <= tickets


def test_humongous_sensitive_notes(reference, manifest, roles):
    notes = [n for n in reference["ticketnotes"] if n["_lookups"]["spk_TicketId"][2] == roles["humongous_claims_certificate"]]
    internal = [n["spk_body"] for n in notes if n["spk_isinternal"]]
    assert any("invoice" in b for b in internal) and any("APP02" in b and "APP03" in b for b in internal)
    assert not any("invoice" in n["spk_body"] or "APP02" in n["spk_body"] for n in notes if not n["spk_isinternal"])


def test_restricted_records(reference, manifest, roles):
    owned = [r for name, rows in reference.items() if isinstance(rows, list) and name != "newincidents"
             for r in rows if isinstance(r, dict) and r.get("_owner_team")]
    assert len(owned) == manifest["restricted"]["records"]
    assert all(r["_owner_team"] == "Relecloud Regulated Accounts" for r in owned)
    lamna_open = [number(t) for t in reference["tickets"] if customer_of(t) == "CUST-014" and t["spk_status"] in OPEN]
    assert sorted(lamna_open) == sorted([roles["lamna_new_starter"], roles["lamna_reimaged_laptop"]])


# =============================================================================== schema and text

def test_schema_matches_the_data(reference):
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    choices = {c["name"]: {o["label"]: o["value"] for o in c["options"]} for c in schema["globalChoices"]}
    for name, values in catalog.CHOICES.items():
        assert choices[name] == values, name
    tables = {t["logicalName"]: t for t in schema["tables"] + schema["extendTables"]}
    standard = {"account": {"name", "address1_city", "websiteurl", "description"},
                "contact": {"firstname", "lastname", "jobtitle", "emailaddress1", "telephone1", "mobilephone"}}
    files = {"businesscalendars": "spk_businesscalendar", "slapolicies": "spk_slapolicy", "technicians": "spk_technician",
             "accounts": "account", "contacts": "contact", "customerprocedures": "spk_customerprocedure",
             "customerdocuments": "spk_customerdocument", "runbooks": "spk_runbook",
             "knowledgearticles": "spk_knowledgearticle", "tickets": "spk_ticket", "ticketnotes": "spk_ticketnote",
             "newincidents": "spk_ticket"}
    for name, table in files.items():
        t = tables[table]
        columns = {c["schemaName"].lower(): c for c in t["columns"]}
        known = set(columns) | standard.get(table, set()) | ({"spk_name"} if "primaryName" in t else set())
        lookups = {lk["schemaName"] for lk in t.get("lookups", [])} | {"parentcustomerid_account", "primarycontactid"}
        for record in reference[name]:
            for key, value in record.items():
                if key.startswith("_"):
                    continue
                assert key in known, f"{name}.{key} is not in schema.json"
                col = columns.get(key)
                if col and col["type"] == "Picklist" and value is not None:
                    assert value in choices[col["globalChoice"]].values(), f"{name}.{key}={value}"
                if col and col["type"] in ("String", "Memo") and value is not None:
                    assert len(value) <= col["maxLength"], f"{name}.{key} longer than {col['maxLength']}"
            assert set(record.get("_lookups", {})) <= lookups
    platform_columns = {"spk_name", "name", "fullname", "parentcustomerid", "jobtitle", "emailaddress1", "telephone1",
                        "mobilephone"}
    for table, views in schema["views"].items():
        known = {c["schemaName"].lower() for c in tables[table]["columns"]} | platform_columns \
            | {lk["schemaName"].lower() for lk in tables[table].get("lookups", [])}
        for v in views:
            assert set(v["columns"]) <= known, (table, v["name"])
    for table, sections in list(schema["forms"].items()) + [(k, v) for k, v in schema["extendForms"].items() if k[0] != "$"]:
        known = {c["schemaName"].lower() for c in tables[table]["columns"]} | {
            lk["schemaName"].lower() for lk in tables[table].get("lookups", [])} | {"spk_name"}
        for s in sections:
            assert set(s["columns"]) <= known, (table, s["section"])
    subareas = {s for area in schema["app"]["sitemap"] for g in area["groups"] for s in g["subareas"]}
    assert {"spk_customerdocument", "spk_agentaction"} <= subareas
    names = {v["name"] for vs in schema["views"].values() for v in vs}
    assert {"Managed Customers", "Customer Procedures", "Customer Contacts", "All Articles", "All Runbooks",
            "Active Technicians", "All Tickets", "Open Tickets", "Untriaged Tickets", "Escalated Tickets",
            "Open Tickets by SLA Remaining", "All Ticket Notes", "All Customer Documents", "All Agent Actions",
            "Denied Agent Actions"} <= names


def test_text_has_no_dashes(reference):
    text = json.dumps(reference, ensure_ascii=False)
    for bad in FORBIDDEN:
        assert bad not in text
    sources = list(SEED_DIR.glob("*.py")) + [SCHEMA_PATH, SETUP_DIR / "DATA-SPEC.md", Path(__file__),
                                            SCHEMA_PATH.parent / "Deploy-ServiceDeskSchema.ps1"]
    for path in sources:
        content = path.read_text(encoding="utf-8")
        for bad in FORBIDDEN:
            assert bad not in content, f"{path.name} contains a forbidden dash"


def test_data_spec_quotes_only_published_numbers(manifest):
    published = set(re.findall(r"TCK-\d{5}", json.dumps(manifest)))
    quoted = set(re.findall(r"TCK-\d{5}", (SETUP_DIR / "DATA-SPEC.md").read_text(encoding="utf-8")))
    ranges = {"TCK-10001", "TCK-10500", "TCK-10501", "TCK-10560"}
    assert quoted - ranges <= published, sorted(quoted - ranges - published)
    notes = set(re.findall(r"TCK-\d{5}-N\d+", (SETUP_DIR / "DATA-SPEC.md").read_text(encoding="utf-8")))
    assert notes <= {c["note"] for c in manifest["scenarios"]["card_number_tickets"]["notes"]}


def test_note_times(reference, manifest):
    anchor = parse(manifest["anchor"])
    for n in reference["ticketnotes"]:
        when = parse(n["spk_notedon"])
        assert when <= anchor
        assert bizhours.is_business_time(when) or (when.weekday() < 5 and when.hour == 18 and when.minute == 0)


# =============================================================================== determinism

def test_two_runs_are_byte_identical(tmp_path, monkeypatch):
    outputs = []
    for run in ("a", "b"):
        out = tmp_path / run
        monkeypatch.setattr(sys, "argv", ["generate_seed.py", "--out", str(out), "--anchor", "2026-10-07T14:00:00Z"])
        assert generate_seed.main() == 0
        outputs.append({p.name: p.read_bytes() for p in sorted(out.glob("*.json"))})
    assert outputs[0] == outputs[1] and len(outputs[0]) == 15


@pytest.mark.parametrize("anchor", anchors(), ids=lambda a: a.strftime("%Y%m%dT%H"))
def test_anchor_invariance(reference, anchor):
    data = generate_seed.build(anchor, SEED)
    assert signature(data) == signature(reference)

    history = [t for t in data["tickets"] if t["spk_status"] in CLOSED]
    opened_open = [parse(t["spk_openedon"]) for t in data["tickets"] if t["spk_status"] in OPEN]
    assert len(history) == 500 and len(opened_open) == 60
    assert max(parse(t["spk_openedon"]) for t in history) < min(opened_open)
    assert max(parse(t["spk_resolvedon"]) for t in history) <= anchor - timedelta(hours=4)
    assert max(parse(n["spk_notedon"]) for n in data["ticketnotes"]) <= anchor
    # The new incidents are the newest tickets and never open after the snapshot.
    for t in data["newincidents"]:
        assert max(opened_open) < parse(t["spk_openedon"]) <= anchor
    # Numbers stay in opening order in every range.
    for group in (history, [t for t in data["tickets"] if t["spk_status"] in OPEN]):
        ordered = sorted(group, key=number)
        assert [t["spk_openedon"] for t in ordered] == sorted(t["spk_openedon"] for t in ordered)
