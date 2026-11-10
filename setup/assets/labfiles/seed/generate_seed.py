#!/usr/bin/env python3
"""Generate the Relecloud service desk seed dataset as Dataverse-shaped JSON.

Usage:
    python generate_seed.py --out data [--anchor auto|2026-10-07T14:00:00Z] [--seed 20261001]

The anchor is the SLA snapshot instant ("SLA Calculated On"). With --anchor auto it is
derived from the current time by bizhours.snap_anchor, so a fresh seed always looks recent.
For a given seed the content is identical for every anchor: ticket numbers, customers,
priorities, notes and counts never change, only the dates move (the history is generated
against REFERENCE_ANCHOR and shifted by whole weeks; setup/tests checks this across a year
of anchors). Two runs with the same seed and anchor write byte-identical files.

Volumes (lab version 3): 500 historical tickets (TCK-10001 to TCK-10500, in the order they
were opened), 60 open tickets (TCK-10501 to TCK-10560, in the order they were opened) and
two new incidents (TCK-10561 and TCK-10562). Hand-authored tickets have role keys; the
manifest publishes the number of every role key and the facts the guides quote
("role_keys" and "scenarios").

Output files (one JSON array per table, records keyed by alternate key):
    businesscalendars.json slapolicies.json technicians.json accounts.json contacts.json
    customerprocedures.json customerdocuments.json runbooks.json knowledgearticles.json
    tickets.json ticketnotes.json annotations.json account_patches.json manifest.json
    newincidents.json   loaded only after the search export, so these tickets are never indexed

Record conventions understood by load_seed.py:
    "_key":        {alternate key column: value}
    "_match":      {column: value} for tables without an alternate key (annotations)
    "_lookups":    {navigation property: [entity set, alternate key column, value]}
    "_owner_team": name of the Dataverse team that owns the record (restricted customers)
    every other key is a Dataverse column logical name with its value.
"""
from __future__ import annotations

import argparse
import base64
import io
import json
import math
import random
import sys
import zipfile
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path
from xml.sax.saxutils import escape

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bizhours  # noqa: E402
from catalog import (  # noqa: E402
    CATEGORY_OWNERS, CATEGORY_TEAMS, CHOICES, CONTACT_ROLES, CUSTOMERS, FIRST_NAMES, KB_ARTICLES, LAST_NAMES,
    LEGACY_CATEGORY_TEAMS, MSP_DOMAIN, PRIORITY_LABELS, PRIORITY_RULES, SLA_RESOLUTION_HOURS, SLA_RESPONSE_HOURS,
    TEAMS, TECHNICIANS,
)
from customer_documents import build_documents  # noqa: E402
from exercise_tickets import OPEN_TICKETS  # noqa: E402
from history_additions import DUPLICATES, NEW_TEMPLATES, V3_STREAM_OFFSET  # noqa: E402
from operations import (  # noqa: E402
    BILLING_RULE, CARD_NUMBER, CHANGE_RULES, CONFIG_DOCUMENT, ESCALATION_HOURS, ESCALATION_RULES,
    INCOMPLETE_TICKET, NEW_INCIDENTS, RUNBOOKS, SENSITIVE_NOTES, SPECIAL_PROCEDURES, TECHNICIAN_BY_ARTICLE,
)
from ticket_templates import (  # noqa: E402
    APP_NAMES, LEGACY_AUDIENCE, LEGACY_CONTRACT_NOTES, LEGACY_OUTCOMES, LEGACY_PRIORITY_TEXT,
    LEGACY_RESOLUTION_FOR_CONTRACT, LEGACY_RESOLUTION_FOR_PRIORITY, PRINTER_NAMES, TEMPLATES, WEEKDAYS,
)

HISTORY_SCALE = 1.6
FIRST_TICKET_NUMBER = 10001
HISTORY_TARGET = 500
OPEN_TARGET = 60
# Historical tickets are generated against this fixed instant and then moved by a whole
# number of weeks to the real anchor, so every environment gets the same history (ticket
# numbers, customers, priorities, notes) whenever it was seeded. Only the dates move.
REFERENCE_ANCHOR = datetime(2026, 10, 7, 14, 0, tzinfo=timezone.utc)
NO_SCALE = {"KB0058", "KB0028", "KB0067", "KB0047"}
PRODUCT_FIELD = {
    "Relecloud Backup Agent": "rba",
    "Relecloud Remote Access": "rra",
    "Relecloud Secure Gateway": "rsg",
    "Relecloud Endpoint Agent": "rea",
}
PRODUCT_TAG = {
    "Relecloud Backup Agent": "backup agent", "Relecloud Remote Access": "remote access",
    "Relecloud Secure Gateway": "gateway", "Relecloud Endpoint Agent": "endpoint agent",
    "Microsoft 365": "microsoft 365", "Line-of-business application": "line-of-business app",
    "Printer or scanner": "printer", "Laptop or desktop": "laptop",
}
VERSION_AT_TIME = {"KB0067": "7.4.0", "KB0028": "5.1.3"}
END_USER_FIRST_NAMES = [
    "Alex", "Brooke", "Chris", "Dmitri", "Eva", "Farah", "George", "Helena", "Isaac", "Joy",
    "Kai", "Laura", "Mohammed", "Nora", "Omar", "Paula", "Rob", "Sara", "Tim", "Valerie",
]
SITE_NAMES = ["head office", "the warehouse", "Branch 2", "the north site", "the distribution site", "the east depot"]
# EXERCISE: Exercise 5 Task 3 narrows the agent's write role so it can't change this team's
# records. The records of these customers are owned by the business unit's default team.
RESTRICTED_TEAM = "Relecloud Regulated Accounts"
RESTRICTED_CUSTOMERS = {"CUST-014"}
DOCX_MIME = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
OPEN_STATUSES = ("New", "In Progress", "Waiting on Customer")


def iso(dt: datetime | None) -> str | None:
    if dt is None:
        return None
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def choice(table: str, label: str | None) -> int | None:
    if label is None:
        return None
    return CHOICES[table][label]


def abbreviation(name: str) -> str:
    letters = [w[0] for w in name.replace(".", " ").replace("'", "").split() if w[0].isalpha()]
    return "".join(letters[:3]).upper()


def applies_to_text(kb: dict) -> tuple[str, str, str, str]:
    parts = []
    versions = kb["versions"]
    labels = {"rba": "Relecloud Backup Agent", "rra": "Remote Access client", "rsg": "Secure Gateway firmware",
              "rea": "Endpoint Agent"}
    version_text = []
    for field, prefixes in versions.items():
        pretty = []
        for p in prefixes:
            pretty.append(p + "x" if p.endswith(".") else (p if p.count(".") >= 2 else p + ".x"))
        version_text.append(f"{labels[field]} {' and '.join(pretty)}")
    if version_text:
        parts.append("; ".join(version_text) + ".")
    else:
        parts.append("All product versions.")
    tiers = kb["tiers"]
    parts.append(("SLA tiers: " + ", ".join(tiers) + ".") if tiers else "All SLA tiers.")
    contracts = kb["contracts"]
    parts.append(("Contract types: " + ", ".join(contracts) + ".") if contracts else "All contract types.")
    return (" ".join(parts), "; ".join(version_text) or "All versions",
            ", ".join(tiers) or "All tiers", ", ".join(contracts) or "All contracts")


def eligible(customer: dict, spec: dict) -> bool:
    if customer["code"] in spec.get("exclude", []):
        return False
    if customer["sites"] < spec.get("min_sites", 1):
        return False
    for field, prefixes in spec.get("versions", {}).items():
        if not any(customer[field].startswith(p) for p in prefixes):
            return False
    if spec.get("tiers") and customer["tier"] not in spec["tiers"]:
        return False
    if spec.get("contracts") and customer["contract"] not in spec["contracts"]:
        return False
    return True


def patch_tuesdays(anchor: datetime, days_back: int) -> list[datetime]:
    """Second Tuesday of each month in the window (monthly patching day)."""
    result = []
    cursor = anchor.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    for _ in range(math.ceil(days_back / 28) + 2):
        first = cursor
        offset = (1 - first.weekday()) % 7  # Tuesday = 1
        second_tuesday = first + timedelta(days=offset + 7)
        if timedelta(days=2) <= anchor - second_tuesday <= timedelta(days=days_back):
            result.append(second_tuesday)
        cursor = (cursor - timedelta(days=1)).replace(day=1)
    return sorted(result)


def business_start(day: datetime, rng: random.Random) -> datetime:
    """A business-hours timestamp on `day` (moved to Monday if it falls at the weekend)."""
    while day.weekday() not in bizhours.WORKDAYS:
        day += timedelta(days=1)
    hour = rng.randint(bizhours.DAY_START_HOUR, bizhours.DAY_END_HOUR - 2)
    minute = rng.choice([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55])
    return day.replace(hour=hour, minute=minute, second=0, microsecond=0)


def escalation_for(customer_code: str, category: str | None, kb_number: str | None, prio: int | None) -> dict | None:
    """First matching rule from operations.ESCALATION_RULES, or None."""
    for rule in ESCALATION_RULES:
        if "priority" in rule and rule["priority"] != prio:
            continue
        if "customer" in rule and rule["customer"] != customer_code:
            continue
        if "category" in rule and rule["category"] != category:
            continue
        if "article" in rule and rule["article"] != kb_number:
            continue
        return rule
    return None


def product_tag(product: str | None, version: str | None) -> str | None:
    if not product or product not in PRODUCT_TAG:
        return None
    if product in PRODUCT_FIELD:
        return f"{PRODUCT_TAG[product]} {'.'.join(version.split('.')[:2])}" if version else None
    return PRODUCT_TAG[product]


def tags_text(base: list[str], product: str | None, version: str | None) -> str:
    tags = list(base)
    extra = product_tag(product, version)
    if extra and extra not in tags:
        tags.append(extra)
    return ", ".join(tags[:5])


def first_sentence(text: str) -> str:
    return text.split(". ")[0].rstrip(".")


def capitalized(text: str) -> str:
    """Titles built from a placeholder such as {app} start with a capital letter."""
    return text[:1].upper() + text[1:]


def build_docx(title: str, paragraphs: list[str]) -> bytes:
    """A minimal, deterministic Word document. docProps/custom.xml is where a sensitivity
    label is recorded (provisioning stamps it with the tenant's label ID)."""
    body = "".join(f"<w:p><w:r><w:t xml:space=\"preserve\">{escape(p)}</w:t></w:r></w:p>" for p in paragraphs)
    parts = {
        "[Content_Types].xml": (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
            '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
            '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
            '<Override PartName="/docProps/custom.xml" ContentType="application/vnd.openxmlformats-officedocument.custom-properties+xml"/>'
            '</Types>'),
        "_rels/.rels": (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
            '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
            '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
            '<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/custom-properties" Target="docProps/custom.xml"/>'
            '</Relationships>'),
        "word/document.xml": (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
            f'<w:body>{body}</w:body></w:document>'),
        "docProps/core.xml": (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
            'xmlns:dc="http://purl.org/dc/elements/1.1/">'
            f'<dc:title>{escape(title)}</dc:title><dc:creator>Relecloud Managed Services</dc:creator>'
            '</cp:coreProperties>'),
        "docProps/app.xml": (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
            '<Application>Relecloud seed generator</Application></Properties>'),
        "docProps/custom.xml": (
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/custom-properties" '
            'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"></Properties>'),
    }
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, content in parts.items():
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            zf.writestr(info, content.encode("utf-8"))
    return buffer.getvalue()


# =============================================================================== history
# A historical ticket is first built as a draft in the reference frame (no number, dates
# not yet shifted). Drafts from all streams are then sorted by opening time and numbered.

def _is_request(kb: dict | None) -> bool:
    return bool(kb) and kb["cause"].startswith("Not a fault")


def _ack_text(first: str, channel: str, kb: dict | None) -> str:
    if channel == "Monitoring Alert":
        return f"Hi {first}, our monitoring raised an alert for this and we are looking into it now. We will keep you updated on this ticket."
    if _is_request(kb):
        return f"Hi {first}, thanks for your request. We are working on it and will keep you updated on this ticket."
    return f"Hi {first}, thanks for reporting this. We are looking into it now and will keep you updated on this ticket."


def _closing_text(first: str, outcome: str, resolution: str, kb: dict | None) -> str:
    summary = first_sentence(resolution)
    if outcome == "Cancelled by customer":
        return f"Hi {first}, as agreed we have closed this request without doing the work. Please raise a new ticket if you want to go ahead later."
    if outcome == "Workaround provided":
        return f"Hi {first}, this is working again for now. {summary}. We will follow up on a lasting fix; please reply if it happens again."
    if outcome == "No fault found":
        return f"Hi {first}, we checked this and found no fault to fix. {summary}. Please reply if it happens again."
    if outcome == "Resolved by vendor":
        return f"Hi {first}, this is now resolved with the vendor's help. {summary}. Please reply if anything else comes up."
    if outcome == "User guidance":
        return f"Hi {first}, here is what we found. {summary}. Please reply if anything else comes up."
    if _is_request(kb):
        return f"Hi {first}, this request is now complete. {summary}. Please reply if anything else comes up."
    return f"Hi {first}, this is now resolved. {summary}. Please reply if anything else comes up."


def _sla_plan(rng: random.Random, opened: datetime, target: float, ref: datetime) -> tuple[datetime, float, datetime, str]:
    breached = rng.random() < 0.12
    factor = rng.uniform(1.05, 1.6) if breached else rng.uniform(0.15, 0.95)
    elapsed_plan = max(0.5, round(target * factor * 2) / 2)
    resolved = bizhours.add_business_hours(opened, elapsed_plan)
    if resolved >= ref - timedelta(hours=4):
        resolved = bizhours.subtract_business_hours(ref, 4)
    elapsed = bizhours.business_hours_between(opened, resolved)
    due = bizhours.add_business_hours(opened, target)
    return resolved, elapsed, due, bizhours.sla_status(target, elapsed, resolved=True)


def _audience(kb_number: str, field: str, options: list[str], drawn: str, affected: int) -> str:
    """Swap a drawn option written for several people when one is affected, and back."""
    rule = LEGACY_AUDIENCE.get((kb_number, field))
    if not rule:
        return drawn
    idx = options.index(drawn)
    if affected <= 1 and idx in rule["multi"]:
        return rule.get("single_text") or options[rule["single"][0]]
    if affected > 1 and idx in rule["single"]:
        return rule.get("multi_text") or options[rule["multi"][0]]
    return drawn


def _legacy_history(rng: random.Random, ref: datetime, history_cutoff: datetime, tuesdays: list[datetime],
                    kb_by_number: dict, contacts_by_customer: dict) -> list[dict]:
    """The original 431 historical tickets. The random calls happen exactly as in lab
    version 2 (same order, same list lengths), so these tickets keep their customers,
    priorities, texts, technicians and SLA results. Text fixes that must agree with the
    ticket's own impact or contract are applied after the draws and use no random numbers."""
    planned = []
    for spec in TEMPLATES:
        kb = kb_by_number[spec["kb"]]
        merged = {"versions": spec.get("versions", kb["versions"]), "tiers": spec.get("tiers", kb["tiers"]),
                  "contracts": spec.get("contracts", kb["contracts"]), "exclude": spec.get("exclude", [])}
        pool = [c for c in CUSTOMERS if eligible(c, merged)]
        if not pool:
            raise SystemExit(f"Template {spec['kb']} has no eligible customer")
        count = spec["weight"] if spec["kb"] in NO_SCALE else round(spec["weight"] * HISTORY_SCALE)
        weights = [math.sqrt(c["seats"]) for c in pool]
        lo, hi = spec["days"]
        for _ in range(count):
            cust = rng.choices(pool, weights=weights, k=1)[0]
            if spec.get("patch_cycle"):
                eligible_tuesdays = [t for t in tuesdays if lo <= (ref - t).days <= hi]
                base = rng.choice(eligible_tuesdays) + timedelta(days=rng.choice([1, 1, 2]))
            else:
                base = ref - timedelta(days=rng.randint(lo, hi))
            opened = business_start(base, rng)
            while opened >= history_cutoff:
                opened = business_start(opened - timedelta(days=rng.randint(3, 7)), rng)
            impacts = spec["impacts"]
            prio, u_lo, u_hi, _w = rng.choices(impacts, weights=[x[3] for x in impacts], k=1)[0]
            if spec.get("tier_priority"):
                prio = spec["tier_priority"][cust["tier"]]
            affected = rng.randint(u_lo, u_hi)
            planned.append((opened, spec, kb, cust, prio, affected))
    planned.sort(key=lambda h: h[0])

    drafts = []
    for opened, spec, kb, cust, prio, affected in planned:
        contacts = contacts_by_customer[cust["code"]]
        contact = contacts[rng.choices([0, 1, 2], weights=[6, 3, 1], k=1)[0]]
        abbr = abbreviation(cust["name"])
        ctx = {
            "server": f"{abbr}FS0{rng.randint(1, 3)}",
            "device": f"LT-{abbr}{rng.randint(10, 99)}",
            "site": rng.choice(SITE_NAMES),
            "count": rng.randint(3, 40),
            "app": rng.choice(APP_NAMES),
            "printer": rng.choice(PRINTER_NAMES),
            "first": rng.choice(END_USER_FIRST_NAMES),
            "weekday": rng.choice(WEEKDAYS),
        }
        title_raw = rng.choice(spec["titles"])
        description_raw = rng.choice(spec["descriptions"])
        resolution_raw = rng.choice(spec["resolution"])
        category = kb["category"]
        tech_code = rng.choice(LEGACY_CATEGORY_TEAMS[category])
        tech_code = TECHNICIAN_BY_ARTICLE.get(kb["number"], tech_code)
        target = float(SLA_RESOLUTION_HOURS[cust["tier"]][prio])
        resolved, elapsed, due, sla_label = _sla_plan(rng, opened, target, ref)
        internal_draw = rng.choice(spec["internal"]) if rng.random() < 0.65 else None

        # ==== corrections that use no random numbers
        number = kb["number"]
        title_raw = _audience(number, "titles", spec["titles"], title_raw, affected)
        description_raw = _audience(number, "descriptions", spec["descriptions"], description_raw, affected)
        resolution_raw = _audience(number, "resolution", spec["resolution"], resolution_raw, affected)
        priority_texts = LEGACY_PRIORITY_TEXT.get((number, "descriptions"), {}).get(prio, {})
        if description_raw in spec["descriptions"]:
            description_raw = priority_texts.get(spec["descriptions"].index(description_raw), description_raw)
        res_index = spec["resolution"].index(resolution_raw)
        if number in LEGACY_RESOLUTION_FOR_CONTRACT and cust["contract"] in LEGACY_RESOLUTION_FOR_CONTRACT[number]:
            res_index = LEGACY_RESOLUTION_FOR_CONTRACT[number][cust["contract"]]
        if number in LEGACY_RESOLUTION_FOR_PRIORITY and prio in LEGACY_RESOLUTION_FOR_PRIORITY[number]:
            res_index = LEGACY_RESOLUTION_FOR_PRIORITY[number][prio]
        resolution_raw = spec["resolution"][res_index]
        outcome = LEGACY_OUTCOMES[number][res_index]
        fmt = dict(ctx, rba=cust["rba"], rra=cust["rra"], rsg=cust["rsg"], rea=cust["rea"])
        if affected >= 2:
            fmt["count"] = affected
        resolution = resolution_raw.format(**fmt)
        notes_suffix = LEGACY_CONTRACT_NOTES.get(number)
        if notes_suffix:
            resolution += notes_suffix.get(cust["contract"], notes_suffix["*"])
        product = kb["product"]
        field = PRODUCT_FIELD.get(product)
        version = VERSION_AT_TIME.get(number) or (cust[field] if field else None)
        drafts.append({
            "stream": "legacy", "opened": opened, "resolved": resolved, "due": due, "elapsed": elapsed,
            "target": target, "sla_label": sla_label, "cust": cust, "contact": contact, "kb": kb, "prio": prio,
            "affected": affected, "title": capitalized(title_raw.format(**fmt)), "description": description_raw.format(**fmt),
            "resolution": resolution, "outcome": outcome, "category": category, "subcategory": kb["subcategory"],
            "product": product, "version": version, "tech": tech_code, "channel": spec.get("channel", "Email"),
            "internal": internal_draw.format(**fmt) if internal_draw else None, "ctx": ctx,
            "tags": tags_text(kb["tags"], product, version),
        })
    return drafts


def _v3_history(rng: random.Random, ref: datetime, history_cutoff: datetime, tuesdays: list[datetime],
                kb_by_number: dict, contacts_by_customer: dict, customer_by_code: dict) -> list[dict]:
    """The historical tickets added in lab version 3, from their own random stream."""
    drafts = []
    for spec in NEW_TEMPLATES:
        kb = kb_by_number[spec["kb"]]
        merged = {"versions": kb["versions"], "tiers": kb["tiers"], "contracts": kb["contracts"],
                  "exclude": spec.get("exclude", []), "min_sites": spec.get("min_sites", 1)}
        pinned = [customer_by_code[c] for c in spec.get("customers", [])]
        for c in pinned:
            if not eligible(c, merged):
                raise SystemExit(f"Template {spec['kb']} pins {c['code']}, which the article does not apply to")
        pool = [] if pinned else [c for c in CUSTOMERS if eligible(c, merged)]
        if not pinned and not pool:
            raise SystemExit(f"Template {spec['kb']} has no eligible customer")
        weights = [math.sqrt(c["seats"]) for c in pool]
        for k in range(spec["count"]):
            cust = pinned[k % len(pinned)] if pinned else rng.choices(pool, weights=weights, k=1)[0]
            if spec.get("days_list"):
                base = ref - timedelta(days=spec["days_list"][k])
            elif spec.get("patch_cycle"):
                lo, hi = spec["days"]
                base = rng.choice([t for t in tuesdays if lo <= (ref - t).days <= hi]) + timedelta(days=rng.choice([1, 2]))
            else:
                lo, hi = spec["days"]
                base = ref - timedelta(days=rng.randint(lo, hi))
            opened = business_start(base, rng)
            while opened >= history_cutoff:
                opened = business_start(opened - timedelta(days=rng.randint(3, 7)), rng)
            prio, u_lo, u_hi, _w = rng.choices(spec["impacts"], weights=[x[3] for x in spec["impacts"]], k=1)[0]
            affected = rng.randint(u_lo, u_hi)
            contact = contacts_by_customer[cust["code"]][rng.choices([0, 1, 2], weights=[6, 3, 1], k=1)[0]]
            abbr = abbreviation(cust["name"])
            ctx = {
                "server": f"{abbr}FS0{rng.randint(1, 3)}", "device": f"LT-{abbr}{rng.randint(10, 99)}",
                "site": spec.get("site") or rng.choice(SITE_NAMES), "count": affected if affected >= 2 else rng.randint(3, 40),
                "app": rng.choice(APP_NAMES), "printer": rng.choice(PRINTER_NAMES),
                "first": rng.choice(END_USER_FIRST_NAMES), "weekday": rng.choice(WEEKDAYS),
            }
            fmt = dict(ctx, rba=cust["rba"], rra=cust["rra"], rsg=cust["rsg"], rea=cust["rea"])
            if spec.get("sequence"):
                title, description = spec["titles"][k], spec["descriptions"][k]
                resolution, outcome = spec["resolutions"][k]
                internal = spec["internal"][k]
            else:
                title, description = rng.choice(spec["titles"]), rng.choice(spec["descriptions"])
                options = spec.get("resolutions") or spec["resolutions_by_contract"].get(
                    cust["contract"], spec["resolutions_by_contract"].get("*"))
                resolution, outcome = rng.choice(options)
                internal = rng.choice(spec["internal"]) if rng.random() < 0.75 else None
            category = kb["category"]
            tech_code = TECHNICIAN_BY_ARTICLE.get(kb["number"]) or rng.choice(CATEGORY_TEAMS[category])
            target = float(SLA_RESOLUTION_HOURS[cust["tier"]][prio])
            resolved, elapsed, due, sla_label = _sla_plan(rng, opened, target, ref)
            product = kb["product"]
            field = PRODUCT_FIELD.get(product)
            version = cust[field] if field else None
            drafts.append({
                "stream": "v3", "opened": opened, "resolved": resolved, "due": due, "elapsed": elapsed,
                "target": target, "sla_label": sla_label, "cust": cust, "contact": contact, "kb": kb, "prio": prio,
                "affected": affected, "title": capitalized(title.format(**fmt)), "description": description.format(**fmt),
                "resolution": resolution.format(**fmt), "outcome": outcome, "category": category,
                "subcategory": kb["subcategory"], "product": product, "version": version, "tech": tech_code,
                "channel": spec.get("channel", "Email"), "internal": internal.format(**fmt) if internal else None,
                "ctx": ctx, "tags": tags_text(kb["tags"], product, version),
            })
    return drafts


def _duplicates(legacy: list[dict], contacts_by_customer: dict) -> list[dict]:
    """A second report of an outage already being worked, closed as Duplicate."""
    drafts = []
    for spec in DUPLICATES:
        want = spec["master"]
        master = next(d for d in legacy if d["kb"]["number"] == want["kb"] and d["prio"] == want["priority"])
        contacts = contacts_by_customer[master["cust"]["code"]]
        contact = contacts[(contacts.index(master["contact"]) + 1) % len(contacts)]
        opened = bizhours.add_business_hours(master["opened"], spec["after_bh"])
        resolved = bizhours.add_business_hours(opened, 0.5)
        target = master["target"]
        elapsed = bizhours.business_hours_between(opened, resolved)
        drafts.append({
            "stream": "duplicate", "master": master, "opened": opened, "resolved": resolved,
            "due": bizhours.add_business_hours(opened, target), "elapsed": elapsed, "target": target,
            "sla_label": bizhours.sla_status(target, elapsed, resolved=True), "cust": master["cust"],
            "contact": contact, "kb": None, "prio": master["prio"], "affected": master["affected"],
            "title": spec["title"], "description": spec["description"], "resolution": spec["resolution"],
            "outcome": "Duplicate", "category": master["category"], "subcategory": master["subcategory"],
            "product": master["product"], "version": master["version"], "tech": master["tech"],
            "channel": spec["channel"], "internal": None, "ctx": master["ctx"], "tags": master["tags"],
        })
    return drafts


# =============================================================================== build

def build(anchor: datetime, seed: int) -> dict:
    rng = random.Random(seed)
    rng_v3 = random.Random(seed + V3_STREAM_OFFSET)
    data: dict[str, list] = {}

    def restricted(rec: dict, customer_code: str) -> dict:
        if customer_code in RESTRICTED_CUSTOMERS:
            rec["_owner_team"] = RESTRICTED_TEAM
        return rec

    # ============================================================= calendar + SLA policies
    data["businesscalendars"] = [{
        "_key": {"spk_calendarcode": "STD"},
        "spk_name": bizhours.CALENDAR_NAME,
        "spk_description": bizhours.CALENDAR_DESCRIPTION,
        "spk_timezone": "UTC",
        "spk_workdays": "Monday to Friday",
        "spk_daystart": "08:00",
        "spk_dayend": "18:00",
        "spk_hoursperday": float(bizhours.HOURS_PER_DAY),
        "spk_holidays": "None configured for the current period.",
    }]
    data["slapolicies"] = []
    for tier, targets in SLA_RESOLUTION_HOURS.items():
        for prio, hours in targets.items():
            data["slapolicies"].append({
                "_key": {"spk_policycode": f"{tier[:4].upper()}-P{prio}"},
                "spk_name": f"{tier} {PRIORITY_LABELS[prio]}",
                "spk_slatier": choice("spk_slatier", tier),
                "spk_priority": choice("spk_priority", PRIORITY_LABELS[prio]),
                "spk_responsehours": float(SLA_RESPONSE_HOURS[tier][prio]),
                "spk_resolutionhours": float(hours),
                "spk_description": f"{tier} customers, {PRIORITY_LABELS[prio]}: first response within "
                                   f"{SLA_RESPONSE_HOURS[tier][prio]} business hours, resolution within {hours} business hours. "
                                   + PRIORITY_RULES,
                "_lookups": {"spk_CalendarId": ["spk_businesscalendars", "spk_calendarcode", "STD"]},
            })

    # ============================================================= technicians
    data["technicians"] = [{
        "_key": {"spk_techniciancode": t["code"]},
        "spk_name": t["name"],
        "spk_email": t["name"].lower().replace(" ", ".") + "@" + MSP_DOMAIN,
        "spk_team": choice("spk_technicianteam", t["team"]),
        "spk_tier": choice("spk_techniciantier", t["tier"]),
        "spk_isavailable": t["available"],
        "spk_availabilitynote": t["availability"],
        "spk_skills": t["skills"],
    } for t in TECHNICIANS]
    tech_by_code = {t["code"]: t for t in TECHNICIANS}

    # ============================================================= customers + contacts
    data["accounts"], data["contacts"], data["account_patches"] = [], [], []
    contacts_by_customer: dict[str, list[dict]] = {}
    i = 0
    for c in CUSTOMERS:
        data["accounts"].append(restricted({
            "_key": {"spk_customercode": c["code"]},
            "name": c["name"],
            "spk_industry": c["industry"],
            "address1_city": c["city"],
            "spk_slatier": choice("spk_slatier", c["tier"]),
            "spk_contracttype": choice("spk_contracttype", c["contract"]),
            "spk_seatcount": c["seats"],
            "spk_sitecount": c["sites"],
            "spk_backupagentversion": c["rba"],
            "spk_remoteaccessversion": c["rra"],
            "spk_gatewayfirmware": c["rsg"],
            "spk_endpointagentversion": c["rea"],
            "spk_accountmanager": c["account_manager"],
            "spk_servicesinscope": c["services"],
            "spk_configurationnotes": c["configuration"],
            "websiteurl": f"https://www.{c['domain']}",
            "description": c["profile"],
        }, c["code"]))
        contacts_by_customer[c["code"]] = []
        for slot, (job, role) in enumerate(CONTACT_ROLES):
            first = FIRST_NAMES[(i * 7) % len(FIRST_NAMES)]
            last = LAST_NAMES[(i * 11) % len(LAST_NAMES)]
            code = f"{c['code']}-C{slot + 1}"
            rec = {
                "_key": {"spk_contactcode": code},
                "firstname": first,
                "lastname": last,
                "jobtitle": job,
                "spk_contactrole": role,
                "emailaddress1": f"{first.lower()}.{last.lower()}@{c['domain']}",
                "telephone1": f"+1 425 555 01{i:02d}",
                "mobilephone": f"+1 206 555 01{i:02d}",
                "_lookups": {"parentcustomerid_account": ["accounts", "spk_customercode", c["code"]]},
            }
            data["contacts"].append(restricted(rec, c["code"]))
            contacts_by_customer[c["code"]].append({"code": code, "first": first, "last": last, "job": job})
            i += 1
        data["account_patches"].append({
            "_key": {"spk_customercode": c["code"]},
            "_lookups": {"primarycontactid": ["contacts", "spk_contactcode", f"{c['code']}-C1"]},
        })
    customer_by_code = {c["code"]: c for c in CUSTOMERS}

    # ============================================================= customer procedures
    data["customerprocedures"] = []
    procedures_by_customer: dict[str, list[dict]] = {c["code"]: [] for c in CUSTOMERS}

    def add_procedure(customer_code: str, seq: int, proc_type: str, title: str, details: str, applies_to: str,
                      reviewed_days_ago: int) -> None:
        code = f"{customer_code}-PR{seq}"
        data["customerprocedures"].append(restricted({
            "_key": {"spk_procedurecode": code},
            "spk_name": title,
            "spk_proceduretype": choice("spk_proceduretype", proc_type),
            "spk_details": details,
            "spk_appliesto": applies_to,
            "spk_lastreviewedon": (anchor - timedelta(days=reviewed_days_ago)).strftime("%Y-%m-%d"),
            "_lookups": {"spk_CustomerId": ["accounts", "spk_customercode", customer_code]},
        }, customer_code))
        procedures_by_customer[customer_code].append({"code": code, "title": title, "type": proc_type})

    for n, c in enumerate(CUSTOMERS):
        people = contacts_by_customer[c["code"]]
        it_manager, sponsor = people[0], people[2]
        add_procedure(c["code"], 1, "Escalation contacts", "Escalation contacts",
                      f"For P1 and P2 incidents call the IT manager, {it_manager['first']} {it_manager['last']}, first, "
                      f"then the executive sponsor, {sponsor['first']} {sponsor['last']}. {ESCALATION_HOURS[c['tier']]} "
                      f"Account manager: {c['account_manager']}.",
                      "All incidents", 30 + (n * 7) % 60)
        title, details = CHANGE_RULES[c["contract"]]
        add_procedure(c["code"], 2, "Change approval" if c["contract"] != "Fully Managed" else "Maintenance window",
                      title, details, "All changes", 45 + (n * 11) % 90)
        seq = 3
        if c["contract"] == "Break-Fix":
            add_procedure(c["code"], seq, "Billing and quotes", BILLING_RULE[0], BILLING_RULE[1], "All billable work",
                          20 + (n * 5) % 40)
            seq += 1
        for special in SPECIAL_PROCEDURES:
            if special["customer"] == c["code"]:
                add_procedure(c["code"], seq, special["type"], special["title"], special["details"],
                              special["applies_to"], 15 + (n * 3) % 30)
                seq += 1

    # ============================================================= customer documents (version 3)
    documents = build_documents(contacts_by_customer, procedures_by_customer)
    data["customerdocuments"] = [restricted({
        "_key": {"spk_documentcode": d["code"]},
        "spk_name": d["title"],
        "spk_documenttype": choice("spk_documenttype", d["type"]),
        "spk_body": d["body"],
        "spk_version": d["version"],
        "spk_lastreviewedon": (anchor - timedelta(days=d["reviewed_days_ago"])).strftime("%Y-%m-%d"),
        "_lookups": {"spk_CustomerId": ["accounts", "spk_customercode", d["customer"]]},
    }, d["customer"]) for d in documents]

    # ============================================================= runbooks
    data["runbooks"] = [{
        "_key": {"spk_runbookcode": rb["code"]},
        "spk_name": rb["title"],
        "spk_category": choice("spk_category", rb["category"]),
        "spk_product": choice("spk_product", rb["product"]),
        "spk_trigger": rb["trigger"],
        "spk_steps": rb["steps"],
        "spk_escalationpath": rb["escalation"],
        "spk_relatedarticles": rb["related"],
        "spk_lastreviewedon": (anchor - timedelta(days=20 + idx * 9)).strftime("%Y-%m-%d"),
    } for idx, rb in enumerate(RUNBOOKS)]

    # ============================================================= knowledge articles
    data["knowledgearticles"] = []
    kb_by_number = {}
    for kb in KB_ARTICLES:
        applies, versions_text, tiers_text, contracts_text = applies_to_text(kb)
        kb_by_number[kb["number"]] = kb
        data["knowledgearticles"].append({
            "_key": {"spk_articlenumber": kb["number"]},
            "spk_name": kb["title"],
            "spk_category": choice("spk_category", kb["category"]),
            "spk_product": choice("spk_product", kb["product"]),
            "spk_symptom": kb["symptom"],
            "spk_cause": kb["cause"],
            "spk_resolution": kb["resolution"],
            "spk_appliesto": applies,
            "spk_appliestoversions": versions_text,
            "spk_appliestotiers": tiers_text,
            "spk_appliestocontracts": contracts_text,
            "spk_kbstatus": choice("spk_kbstatus", kb["status"]),
            "spk_lastreviewedon": (anchor - timedelta(days=kb["reviewed_days_ago"])).strftime("%Y-%m-%d"),
            "spk_keywords": kb["keywords"],
            "spk_relatedarticles": ", ".join(kb["related"]),
        })

    # ============================================================= tickets
    tickets: list[dict] = []
    notes: list[dict] = []
    note_seq: dict[str, int] = {}

    def ticket_record(number, cust, contact_code, title, description, category, subcategory, prio, status,
                      tech_code, product, version, affected, channel, opened, resolved, resolution, outcome,
                      kb_number, tags, sla_target, sla_elapsed, sla_due, sla_status_label, sla_calc):
        rec = {
            "_key": {"spk_ticketnumber": number},
            "spk_name": title,
            "spk_description": description,
            "spk_category": choice("spk_category", category),
            "spk_subcategory": choice("spk_subcategory", subcategory),
            "spk_priority": choice("spk_priority", PRIORITY_LABELS[prio]) if prio else None,
            "spk_status": choice("spk_ticketstatus", status),
            "spk_product": choice("spk_product", product),
            "spk_productversion": version or None,
            "spk_affectedusers": affected,
            "spk_channel": choice("spk_channel", channel),
            "spk_openedon": iso(opened),
            "spk_resolvedon": iso(resolved),
            "spk_resolutionsummary": resolution,
            "spk_outcome": choice("spk_outcome", outcome),
            "spk_tags": tags or None,
            "spk_slatargethours": sla_target,
            "spk_slaelapsedhours": sla_elapsed,
            "spk_slaremaininghours": None if sla_target is None else round(sla_target - sla_elapsed, 2),
            "spk_sladueon": iso(sla_due),
            "spk_slastatus": choice("spk_slastatus", sla_status_label),
            "spk_slacalculatedon": iso(sla_calc),
            "spk_isescalated": False,
            "_lookups": {
                "spk_CustomerId": ["accounts", "spk_customercode", cust["code"]],
                "spk_ContactId": ["contacts", "spk_contactcode", contact_code],
            },
        }
        if tech_code:
            rec["_lookups"]["spk_AssignedTechnicianId"] = ["spk_technicians", "spk_techniciancode", tech_code]
        if kb_number:
            rec["_lookups"]["spk_RelatedArticleId"] = ["spk_knowledgearticles", "spk_articlenumber", kb_number]
        return restricted(rec, cust["code"])

    def escalate(rec: dict, level: str, reason: str, when: datetime) -> None:
        rec["spk_isescalated"] = True
        rec["spk_escalationlevel"] = choice("spk_escalationlevel", level)
        rec["spk_escalatedon"] = iso(when)
        rec["spk_escalationreason"] = reason

    def add_note(ticket_number, is_internal, author, body, when, customer_code):
        seq = note_seq.get(ticket_number, 0) + 1
        note_seq[ticket_number] = seq
        notes.append(restricted({
            "_key": {"spk_notecode": f"{ticket_number}-N{seq}"},
            "spk_name": (("Internal: " if is_internal else "Reply: ") + body)[:95],
            "spk_body": body,
            "spk_isinternal": is_internal,
            "spk_author": author,
            "spk_notedon": iso(when),
            "_lookups": {"spk_TicketId": ["spk_tickets", "spk_ticketnumber", ticket_number]},
        }, customer_code))

    # ==== historical tickets
    # Generated against REFERENCE_ANCHOR, never against the real anchor, so the random draws
    # (and therefore numbers, customers and notes) don't depend on when the seed runs. The
    # result moves by `shift`, a whole number of weeks, which keeps every weekday and every
    # business-hours figure intact and lands the history just before the real anchor. Every
    # historical ticket opens before the oldest open ticket, so ticket numbers stay
    # chronological across the two ranges.
    ref = REFERENCE_ANCHOR
    shift = timedelta(weeks=math.floor((anchor - ref) / timedelta(weeks=1)))
    tuesdays = patch_tuesdays(ref, 270)
    open_specs = OPEN_TICKETS + [INCOMPLETE_TICKET]
    oldest_open = bizhours.subtract_business_hours(ref, max(t["elapsed_bh"] for t in open_specs))
    history_cutoff = oldest_open - timedelta(hours=1)
    legacy = _legacy_history(rng, ref, history_cutoff, tuesdays, kb_by_number, contacts_by_customer)
    added = _v3_history(rng_v3, ref, history_cutoff, tuesdays, kb_by_number, contacts_by_customer, customer_by_code)
    duplicates = _duplicates(legacy, contacts_by_customer)
    drafts = legacy + added + duplicates
    if len(drafts) != HISTORY_TARGET:
        raise SystemExit(f"Expected {HISTORY_TARGET} historical tickets, built {len(drafts)}")
    order = sorted(range(len(drafts)), key=lambda k: (drafts[k]["opened"], k))
    for position, k in enumerate(order):
        drafts[k]["number"] = f"TCK-{FIRST_TICKET_NUMBER + position}"
    history_numbers = [drafts[k]["number"] for k in order]

    # The sensitive notes (operations.SENSITIVE_NOTES) go on the first original historical
    # ticket of a customer, or on an open ticket by role key, in time order with its other notes.
    first_legacy_ticket: dict[str, dict] = {}
    for k in order:
        if drafts[k]["stream"] == "legacy":
            first_legacy_ticket.setdefault(drafts[k]["cust"]["code"], drafts[k])
    sensitive_notes: list[dict] = []

    def write_notes(ticket_number: str, customer_code: str, entries: list[tuple]) -> None:
        """entries: (when, is_internal, author, body, sensitive spec or None), written in time order."""
        for when, is_internal, author, body, sensitive in sorted(entries, key=lambda n: n[0]):
            if when > anchor:
                raise SystemExit(f"A note on {ticket_number} would be after the anchor")
            add_note(ticket_number, is_internal, author, body, when, customer_code)
            if sensitive:
                sensitive_notes.append({"position": SENSITIVE_NOTES.index(sensitive), "role": sensitive.get("role"),
                                        "customer": customer_code, "ticket": ticket_number,
                                        "note": f"{ticket_number}-N{note_seq[ticket_number]}"})

    for k in order:
        d = drafts[k]
        opened_at, resolved_at, due_at = d["opened"] + shift, d["resolved"] + shift, d["due"] + shift
        status = "Closed" if resolved_at < anchor - timedelta(days=3) else "Resolved"
        resolution = d["resolution"].format(master=d["master"]["number"]) if d["stream"] == "duplicate" else d["resolution"]
        kb = d["kb"]
        rec = ticket_record(d["number"], d["cust"], d["contact"]["code"], d["title"], d["description"],
                            d["category"], d["subcategory"], d["prio"], status, d["tech"], d["product"], d["version"],
                            d["affected"], d["channel"], opened_at, resolved_at, resolution, d["outcome"],
                            kb["number"] if kb else None, d["tags"], d["target"], d["elapsed"], due_at,
                            d["sla_label"], resolved_at)
        rule = None if d["stream"] == "duplicate" else escalation_for(d["cust"]["code"], d["category"],
                                                                      kb["number"], d["prio"])
        escalated_ref = bizhours.add_business_hours(d["opened"], min(1.0, d["elapsed"] / 2))
        if rule:
            escalate(rec, rule["level"], rule["reason"], escalated_ref + shift)
        tickets.append(rec)
        d["record"] = rec
        tech_name = tech_by_code[d["tech"]]["name"]
        first = d["contact"]["first"]
        entries = [(bizhours.add_business_hours(d["opened"], min(0.5, d["elapsed"] / 3)) + shift, False, tech_name,
                    _ack_text(first, d["channel"], kb), None)]
        if d["stream"] == "duplicate":
            master = d["master"]["number"]
            entries.append((bizhours.add_business_hours(d["opened"], 0.4) + shift, True, tech_name,
                            f"Same problem as {master}, already being worked. Linked and closed as a duplicate.", None))
            entries.append((resolved_at, False, tech_name,
                            f"Hi {first}, thanks for letting us know. This is the same problem as ticket {master}, which "
                            f"we are already working on, so we have linked the two and closed this one. Updates will "
                            f"come on {master}.", None))
        else:
            if d["internal"]:
                entries.append((bizhours.add_business_hours(d["opened"], d["elapsed"] / 2) + shift, True, tech_name,
                                d["internal"], None))
            if rule:
                entries.append((escalated_ref + shift, True, tech_name, f"Escalated ({rule['level']}): {rule['reason']}", None))
            entries.append((resolved_at, False, tech_name, _closing_text(first, d["outcome"], resolution, kb), None))
        for s in SENSITIVE_NOTES:
            if first_legacy_ticket.get(s.get("history_customer")) is d:
                entries.append((bizhours.add_business_hours(d["opened"], d["elapsed"] / 3) + shift, s["internal"],
                                s["author"], s["body"], s))
        write_notes(d["number"], d["cust"]["code"], entries)

    # ==== hand-authored open tickets, plus the seeded ticket with too little information
    open_opened = {t["role"]: bizhours.subtract_business_hours(anchor, t["elapsed_bh"]) for t in open_specs}
    open_order = sorted(range(len(open_specs)), key=lambda k: (open_opened[open_specs[k]["role"]], k))
    role_numbers: dict[str, str] = {}
    for position, k in enumerate(open_order):
        role_numbers[open_specs[k]["role"]] = f"TCK-{FIRST_TICKET_NUMBER + HISTORY_TARGET + position}"
    if len(open_specs) != OPEN_TARGET:
        raise SystemExit(f"Expected {OPEN_TARGET} open tickets, found {len(open_specs)}")
    spec_by_role = {t["role"]: t for t in open_specs}
    for k in open_order:
        t = open_specs[k]
        number = role_numbers[t["role"]]
        cust = customer_by_code[t["customer"]]
        contact = contacts_by_customer[cust["code"]][t["contact"]]
        opened = open_opened[t["role"]]
        product = t["product"]
        field = PRODUCT_FIELD.get(product) if product else None
        version = cust[field] if field else None
        prio = t["priority"]
        if prio:
            target = float(SLA_RESOLUTION_HOURS[cust["tier"]][prio])
            elapsed = bizhours.business_hours_between(opened, anchor)
            due = bizhours.add_business_hours(opened, target)
            label = bizhours.sla_status(target, elapsed, resolved=False)
            calc = anchor
        else:
            target = elapsed = due = label = calc = None
        if t["category"] is None:
            tags = None
        elif "tags" in t:
            tags = ", ".join(t["tags"])
        else:
            tags = tags_text(kb_by_number[t["kb"]]["tags"], product, version)
        rec = ticket_record(number, cust, contact["code"], t["title"], t["description"], t["category"],
                            t["subcategory"], prio, t["status"], t["technician"], product, version, t["affected"],
                            t["channel"], opened, None, None, None, t["kb"], tags, target, elapsed, due, label, calc)
        entries = [(bizhours.add_business_hours(opened, after), is_internal, author, body, None)
                   for is_internal, author, body, after in t["notes"]]
        entries += [(bizhours.add_business_hours(opened, s["after_bh"]), s["internal"], s["author"], s["body"], s)
                    for s in SENSITIVE_NOTES if s.get("role") == t["role"]]
        esc = None
        if prio == 1:
            esc = {"level": ESCALATION_RULES[0]["level"], "reason": ESCALATION_RULES[0]["reason"], "after_bh": 0.5}
        elif t.get("escalation"):
            esc = t["escalation"]
        if esc:
            when = bizhours.add_business_hours(opened, esc["after_bh"])
            escalate(rec, esc["level"], esc["reason"], when)
            author = esc.get("author") or tech_by_code[t["technician"]]["name"]
            entries.append((when, True, author, f"Escalated ({esc['level']}): {esc['reason']}", None))
        tickets.append(rec)
        write_notes(number, cust["code"], entries)
    if len(sensitive_notes) != len(SENSITIVE_NOTES):
        raise SystemExit("A sensitive note did not find its ticket")
    # Report them in the order operations.SENSITIVE_NOTES lists them.
    sensitive_notes.sort(key=lambda n: n["position"])
    for n in sensitive_notes:
        del n["position"]

    data["tickets"] = tickets
    data["ticketnotes"] = notes

    # ============================================================= labeled configuration document
    doc = CONFIG_DOCUMENT
    data["annotations"] = [{
        "_match": {"filename": doc["filename"]},
        "subject": doc["subject"],
        "filename": doc["filename"],
        "mimetype": DOCX_MIME,
        "notetext": "Customer configuration document. Its sensitivity label decides whether it may be returned to an AI agent.",
        "isdocument": True,
        "documentbody": base64.b64encode(build_docx(doc["title"], doc["paragraphs"])).decode("ascii"),
        "_lookups": {"objectid_account": ["accounts", "spk_customercode", doc["customer"]]},
    }]

    # ============================================================= new incidents (loaded after the export)
    data["newincidents"] = []
    incident_opened = {t["role"]: bizhours.subtract_business_hours(anchor, t["elapsed_bh"]) for t in NEW_INCIDENTS}
    incident_order = sorted(NEW_INCIDENTS, key=lambda t: incident_opened[t["role"]])
    for position, t in enumerate(incident_order):
        number = f"TCK-{FIRST_TICKET_NUMBER + HISTORY_TARGET + OPEN_TARGET + position}"
        role_numbers[t["role"]] = number
        cust = customer_by_code[t["customer"]]
        contact = contacts_by_customer[cust["code"]][t["contact"]]
        data["newincidents"].append(ticket_record(number, cust, contact["code"], t["title"], t["description"],
                                                  None, None, None, "New", None, None, None, None, t["channel"],
                                                  incident_opened[t["role"]], None, None, None, None, None,
                                                  None, None, None, None, None))

    # ============================================================= manifest
    context = {
        "drafts": drafts, "order": order, "role_numbers": role_numbers, "spec_by_role": spec_by_role,
        "customer_by_code": customer_by_code, "contacts_by_customer": contacts_by_customer,
        "procedures_by_customer": procedures_by_customer, "documents": documents, "kb_by_number": kb_by_number,
        "tech_by_code": tech_by_code, "sensitive_notes": sensitive_notes, "history_numbers": history_numbers,
    }
    data["manifest"] = build_manifest(data, anchor, seed, context)
    return data


# =============================================================================== manifest

def _label(table: str, value: int | None) -> str | None:
    if value is None:
        return None
    return next(label for label, v in CHOICES[table].items() if v == value)


def _summary(rec: dict, customer_by_code: dict, tech_by_code: dict) -> dict:
    """The facts of a ticket that a guide may quote. No dates: they move with the anchor."""
    lookups = rec["_lookups"]
    cust = customer_by_code[lookups["spk_CustomerId"][2]]
    tech = lookups.get("spk_AssignedTechnicianId", [None, None, None])[2]
    kb = lookups.get("spk_RelatedArticleId", [None, None, None])[2]
    out = {
        "ticket": rec["_key"]["spk_ticketnumber"], "customer_code": cust["code"], "customer": cust["name"],
        "tier": cust["tier"], "contract": cust["contract"], "title": rec["spk_name"],
        "status": _label("spk_ticketstatus", rec["spk_status"]), "priority": _label("spk_priority", rec["spk_priority"]),
        "category": _label("spk_category", rec["spk_category"]),
        "subcategory": _label("spk_subcategory", rec["spk_subcategory"]),
        "technician": {"code": tech, "name": tech_by_code[tech]["name"]} if tech else None,
        "related_article": kb,
    }
    if rec["spk_slatargethours"] is not None:
        out["sla"] = {"target_hours": rec["spk_slatargethours"], "elapsed_hours": rec["spk_slaelapsedhours"],
                      "remaining_hours": rec["spk_slaremaininghours"],
                      "status": _label("spk_slastatus", rec["spk_slastatus"])}
    else:
        out["sla"] = None
    if rec["spk_isescalated"]:
        out["escalation"] = {"level": _label("spk_escalationlevel", rec["spk_escalationlevel"]),
                             "reason": rec["spk_escalationreason"]}
    else:
        out["escalation"] = None
    if rec.get("spk_outcome") is not None:
        out["outcome"] = _label("spk_outcome", rec["spk_outcome"])
    return out


def build_manifest(data: dict, anchor: datetime, seed: int, ctx: dict) -> dict:
    customer_by_code, tech_by_code = ctx["customer_by_code"], ctx["tech_by_code"]
    role_numbers, spec_by_role = ctx["role_numbers"], ctx["spec_by_role"]
    tickets = data["tickets"]
    by_number = {t["_key"]["spk_ticketnumber"]: t for t in tickets}
    incidents = {t["_key"]["spk_ticketnumber"]: t for t in data["newincidents"]}
    history = [by_number[n] for n in ctx["history_numbers"]]
    open_status_values = {CHOICES["spk_ticketstatus"][s] for s in OPEN_STATUSES}
    open_records = [t for t in tickets if t["spk_status"] in open_status_values]

    def kb_of(rec):
        return (rec["_lookups"].get("spk_RelatedArticleId") or [None, None, None])[2]

    def cust_of(rec):
        return rec["_lookups"]["spk_CustomerId"][2]

    def summary(number):
        rec = by_number.get(number) or incidents[number]
        return _summary(rec, customer_by_code, tech_by_code)

    def brief(rec):
        return {"ticket": rec["_key"]["spk_ticketnumber"], "customer_code": cust_of(rec),
                "customer": customer_by_code[cust_of(rec)]["name"], "title": rec["spk_name"],
                "priority": _label("spk_priority", rec["spk_priority"])}

    def tech_of(rec):
        code = rec["_lookups"]["spk_AssignedTechnicianId"][2]
        return {"code": code, "name": tech_by_code[code]["name"]}

    def history_for(kb_number):
        return [t for t in history if kb_of(t) == kb_number]

    notes_by_ticket: dict[str, list[dict]] = {}
    for n in data["ticketnotes"]:
        notes_by_ticket.setdefault(n["_lookups"]["spk_TicketId"][2], []).append(n)

    scenarios: dict[str, dict] = {}
    # ================================================================ one entry per role key
    for role, number in role_numbers.items():
        entry = summary(number)
        spec = spec_by_role.get(role)
        entry["role"] = role
        entry["purpose"] = spec["purpose"] if spec else (
            "New incident: unclassified, loaded after the search export so it is never indexed")
        entry["notes"] = [{"code": n["_key"]["spk_notecode"], "internal": n["spk_isinternal"], "author": n["spk_author"]}
                          for n in notes_by_ticket.get(number, [])]
        scenarios[role] = entry

    def role_ref(role):
        return {"role": role, "ticket": role_numbers[role]}

    # ================================================================ SLA set
    def sla_row(role):
        s = scenarios[role]
        return {"role": role, "ticket": s["ticket"], "customer": s["customer"], "tier": s["tier"],
                "priority": s["priority"], "target_hours": s["sla"]["target_hours"],
                "elapsed_hours": s["sla"]["elapsed_hours"], "remaining_hours": s["sla"]["remaining_hours"],
                "status": s["sla"]["status"]}
    ranked = sorted((t for t in open_records if t["spk_slaremaininghours"] is not None),
                    key=lambda t: (t["spk_slaremaininghours"], t["_key"]["spk_ticketnumber"]))
    number_to_role = {v: k for k, v in role_numbers.items()}
    near = [number_to_role[t["_key"]["spk_ticketnumber"]] for t in ranked if 0 <= t["spk_slaremaininghours"] < 6.0]
    breached = [number_to_role[t["_key"]["spk_ticketnumber"]] for t in ranked if t["spk_slaremaininghours"] < 0]
    rest = [t["spk_slaremaininghours"] for t in ranked
            if number_to_role[t["_key"]["spk_ticketnumber"]] not in set(near) | set(breached)]
    untriaged_roles = [r for r, s in spec_by_role.items() if s["priority"] is None]
    scenarios["sla_set"] = {
        "business_hours": "Monday to Friday, 08:00 to 18:00 UTC, no holidays",
        "near_breach": [sla_row(r) for r in near],
        "breached": [sla_row(r) for r in sorted(breached, key=lambda r: scenarios[r]["sla"]["remaining_hours"])],
        "first_five_by_remaining": [t["_key"]["spk_ticketnumber"] for t in ranked[:5]],
        "lowest_remaining_of_the_others": min(rest),
        "open_tickets_with_sla": len(ranked),
        "untriaged_without_sla": [role_ref(r) for r in sorted(untriaged_roles, key=lambda r: role_numbers[r])],
    }

    # ================================================================ Woodgrove Bank
    per_customer = Counter(cust_of(t) for t in open_records)
    woodgrove_open = sorted((t for t in open_records if cust_of(t) == "CUST-007"),
                            key=lambda t: (t["spk_slaremaininghours"], t["_key"]["spk_ticketnumber"]))
    woodgrove_history = [t for t in history if cust_of(t) == "CUST-007"]
    top = Counter(kb_of(t) for t in woodgrove_history).most_common()
    best = top[0][1]
    scenarios["woodgrove_open_tickets"] = {
        "customer_code": "CUST-007", "count": len(woodgrove_open),
        "next_highest_customer_count": max(v for k, v in per_customer.items() if k != "CUST-007"),
        "tickets": [{"role": number_to_role[t["_key"]["spk_ticketnumber"]], "ticket": t["_key"]["spk_ticketnumber"],
                     "title": t["spk_name"], "category": _label("spk_category", t["spk_category"]),
                     "priority": _label("spk_priority", t["spk_priority"]),
                     "status": _label("spk_ticketstatus", t["spk_status"]),
                     "remaining_hours": t["spk_slaremaininghours"], "target_hours": t["spk_slatargethours"]}
                    for t in woodgrove_open],
        "recurring": {"issue": "Remote Access disconnects about every hour", "article": "KB0058",
                      "tickets": [role_numbers[r] for r in ("woodgrove_vpn_relationship_manager", "woodgrove_vpn_branch",
                                                            "woodgrove_vpn_mortgage")]},
        "slow_laptop_article": "KB0067",
        "history": {
            "resolved_or_closed": len(woodgrove_history),
            "most_used_articles": [{"article": k, "tickets": v} for k, v in top if v == best],
            "escalated": [{"ticket": t["_key"]["spk_ticketnumber"], "article": kb_of(t),
                           "level": _label("spk_escalationlevel", t["spk_escalationlevel"])}
                          for t in woodgrove_history if t["spk_isescalated"]],
        },
    }

    # ================================================================ KB0023 and KB0133 history
    kb0023 = history_for("KB0023")
    scenarios["kb0023_history"] = {
        "article": "KB0023", "count": len(kb0023),
        "tickets": [dict(brief(t), technician=tech_of(t), escalation_level=_label("spk_escalationlevel", t.get("spk_escalationlevel")))
                    for t in kb0023],
        "priorities": sorted({_label("spk_priority", t["spk_priority"]) for t in kb0023}),
        "technicians": sorted({tech_of(t)["code"] for t in kb0023}),
        "escalation_levels": sorted({_label("spk_escalationlevel", t.get("spk_escalationlevel")) for t in kb0023}),
        "open_match": role_ref("trey_vault_quota"),
    }
    kb0133 = history_for("KB0133")
    p2 = [t for t in kb0133 if t["spk_priority"] == CHOICES["spk_priority"]["P2 High"]]
    scenarios["kb0133_history"] = {
        "article": "KB0133", "count": len(kb0133),
        "tickets": [dict(brief(t), technician=tech_of(t), escalation_level=_label("spk_escalationlevel", t.get("spk_escalationlevel")))
                    for t in kb0133],
        "technicians": sorted({tech_of(t)["code"] for t in kb0133}),
        "p2_tickets": [t["_key"]["spk_ticketnumber"] for t in p2],
        "p2_escalation_levels": sorted({_label("spk_escalationlevel", t.get("spk_escalationlevel")) for t in p2}),
        "routing_application_tickets": [brief(t) for t in kb0133 if "routing application" in t["spk_name"].lower()],
    }

    # ================================================================ new incidents
    adatum = role_numbers["new_incident_adatum"]
    docs_by_customer: dict[str, list[dict]] = {}
    for d in ctx["documents"]:
        docs_by_customer.setdefault(d["customer"], []).append({"code": d["code"], "type": d["type"], "title": d["title"]})
    decoys = {}
    for kb_number, why in (
            ("KB0012", "The standard response to a failed job for Platinum and Gold customers; not a full vault"),
            ("KB0013", "The standard response to a failed job for Silver and Bronze customers; not a full vault"),
            ("KB0033", "Slow backups after vault encryption was turned on; restore points are still created"),
            ("KB0036", "Large Outlook data files in file backups: an exclusion problem, not a storage limit"),
            ("KB0039", "A device that is offline and not reporting; nothing is wrong with the vault"),
            ("KB0007", "Error RBA-1043, a snapshot timeout after patching")):
        rows = history_for(kb_number)
        decoys[kb_number] = {"why_not": why, "history_count": len(rows), "example": brief(rows[0]),
                             "adatum_tickets": [brief(t) for t in rows if cust_of(t) == "CUST-019"]}
    scenarios["new_incident_adatum_expected"] = {
        "ticket": adatum, "role": "new_incident_adatum", "customer_code": "CUST-019",
        "true_matches": {"article": "KB0023", "history": [t["_key"]["spk_ticketnumber"] for t in kb0023],
                         "open": role_ref("trey_vault_quota")},
        "decoys": decoys, "open_decoy": role_ref("adatum_backup_unknown"),
        "recommendation": {"category": "Backup and Recovery", "subcategory": "Storage quota", "priority": "P3 Medium",
                           "technician": {"code": "TECH-01", "name": "Priya Raman", "team": "Infrastructure", "tier": "L2"},
                           "sla_target_hours": SLA_RESOLUTION_HOURS["Silver"][3], "procedure": "CUST-019-PR3",
                           "account_manager": customer_by_code["CUST-019"]["account_manager"],
                           "escalation_level": "Account Manager", "runbook": "RB-002",
                           "customer_documents": docs_by_customer["CUST-019"]},
    }
    scenarios["new_incident_consolidated_expected"] = {
        "ticket": role_numbers["new_incident_consolidated"], "role": "new_incident_consolidated",
        "customer_code": "CUST-020", "article": "KB0133", "runbook": "RB-005", "procedure": "CUST-020-PR3",
        "recommendation": {"category": "Line-of-Business App", "subcategory": "Certificate", "priority": "P2 High",
                           "technician": {"code": "TECH-06", "name": "Daniel Cho", "team": "Service Desk", "tier": "L1"},
                           "sla_target_hours": SLA_RESOLUTION_HOURS["Silver"][2], "escalation_level": "Vendor",
                           "operations_contact": " ".join(
                               (ctx["contacts_by_customer"]["CUST-020"][1]["first"],
                                ctx["contacts_by_customer"]["CUST-020"][1]["last"])),
                           "affected_server": "CMRT-N01 (north depot)"},
        "history": "kb0133_history",
        "similar_symptom_different_incident": [role_ref("untriaged_lucerne_cert"), role_ref("humongous_claims_certificate")],
        "customer_documents": docs_by_customer["CUST-020"],
    }

    # ================================================================ conflicting pairs and splits
    def customer_values(code, fields):
        c = customer_by_code[code]
        return {f: c[f] for f in fields}
    scenarios["conflicting_pairs"] = {"pairs": [
        {"articles": ["KB0031", "KB0058"], "symptom": "Remote Access disconnects about every hour (RRA-4012)",
         "decided_by": "Remote Access client version and Secure Gateway firmware",
         "examples": [{"customer_code": "CUST-007", "values": customer_values("CUST-007", ["rra", "rsg"]), "article": "KB0058"},
                      {"customer_code": "CUST-019", "values": customer_values("CUST-019", ["rra", "rsg"]), "article": "KB0031"}],
         "open_tickets": {"KB0058": [role_ref(r) for r in ("woodgrove_vpn_branch", "woodgrove_vpn_mortgage",
                                                           "woodgrove_vpn_relationship_manager", "untriaged_fabrikam_vpn")],
                          "KB0031": [role_ref("alpine_vpn_hourly")]},
         "history_counts": {"KB0031": len(history_for("KB0031")), "KB0058": len(history_for("KB0058"))}},
        {"articles": ["KB0012", "KB0013"], "symptom": "A failed job on the overnight backup report",
         "decided_by": "SLA tier", "examples": [{"tiers": ["Platinum", "Gold"], "article": "KB0012"},
                                                {"tiers": ["Silver", "Bronze"], "article": "KB0013"}],
         "history_counts": {"KB0012": len(history_for("KB0012")), "KB0013": len(history_for("KB0013"))}},
        {"articles": ["KB0044", "KB0045"], "symptom": "A firewall rule change request", "decided_by": "Contract type",
         "examples": [{"customer_code": "CUST-007", "contract": "Fully Managed", "article": "KB0044"},
                      {"customer_code": "CUST-009", "contract": "Break-Fix", "article": "KB0045"}],
         "open_tickets": {"KB0044": [role_ref("adventure_firewall_rule")], "KB0045": [role_ref("margies_firewall_quote")]},
         "history_counts": {"KB0044": len(history_for("KB0044")), "KB0045": len(history_for("KB0045"))}},
        {"articles": ["KB0067", "KB0062"],
         "symptom": "Laptops slow for the first hour after sign-in; the Relecloud Endpoint scanner uses high CPU",
         "decided_by": "Endpoint Agent version",
         "examples": [{"customer_code": "CUST-007", "values": customer_values("CUST-007", ["rea"]), "article": "KB0067"},
                      {"customer_code": "CUST-015", "values": customer_values("CUST-015", ["rea"]), "article": "KB0062"}],
         "open_tickets": {"KB0067": [role_ref("woodgrove_slow_laptop")], "KB0062": [role_ref("trey_slow_signin")]},
         "history_counts": {"KB0067": len(history_for("KB0067")), "KB0062": len(history_for("KB0062"))},
         "note": "Customers on Endpoint Agent 7.4.1 already have the fix for both."},
    ], "other_applicability_splits": [
        {"articles": ["KB0073", "KB0074"], "decided_by": "Contract type",
         "open_tickets": {"KB0073": [role_ref("fabrikam_new_laptop")], "KB0074": [role_ref("tailspin_laptop_quote")]}},
        {"articles": ["KB0033", "KB0014"], "decided_by": "Backup Agent version (5.x or 4.x)",
         "open_tickets": {"KB0014": [role_ref("margies_backup_slow")]}},
    ], "retired": {"article": "KB0019", "superseded_by": "KB0007", "indexed": True}}

    # ================================================================ incomplete tickets
    scenarios["incomplete_tickets"] = {"tickets": [
        dict(role_ref("incomplete_vanarsdel"), status="New", untriaged=True, missing=INCOMPLETE_TICKET["missing"]),
        dict(role_ref("incomplete_wingtip_email"), status="Waiting on Customer", untriaged=False,
             missing=["a bounce message (non-delivery report), or confirmation that there was none",
                      "the address of a customer who did not receive the email", "when the email was sent",
                      "how many senders and recipients are affected"]),
    ], "expected": "The agent asks for the missing details instead of guessing a cause, priority or article."}

    # ================================================================ recurring issues
    def kb_history_for_customer(kb_number, code):
        return [t["_key"]["spk_ticketnumber"] for t in history_for(kb_number) if cust_of(t) == code]
    scenarios["recurring_issues"] = {"issues": [
        {"customer_code": "CUST-007", "issue": "Remote Access disconnects about every hour since the firmware rollout",
         "article": "KB0058", "open": [role_ref(r) for r in ("woodgrove_vpn_relationship_manager", "woodgrove_vpn_branch",
                                                            "woodgrove_vpn_mortgage")],
         "history": [], "occurrences": 3},
        {"customer_code": "CUST-012", "issue": "The Store 2 router keeps restarting", "article": "KB0059",
         "history": kb_history_for_customer("KB0059", "CUST-012"), "open": [role_ref("fourthcoffee_router_quote")],
         "occurrences": len(kb_history_for_customer("KB0059", "CUST-012")) + 1},
        {"customer_code": "CUST-006", "issue": "Customs filings rejected after a vendor update", "article": "KB0130",
         "history": kb_history_for_customer("KB0130", "CUST-006"), "open": [role_ref("wwi_customs_rejected")],
         "occurrences": len(kb_history_for_customer("KB0130", "CUST-006")) + 1},
    ]}

    # ================================================================ similar symptoms, different incidents
    scenarios["similar_symptoms"] = {
        "symptom": "Users see that a line-of-business application's security certificate has expired",
        "tickets": [
            dict(role_ref("untriaged_lucerne_cert"), customer_code="CUST-008",
                 incident="Lucerne's payroll application on its own server LPAPP01, administered by Lucerne's IT team"),
            dict(role_ref("new_incident_consolidated"), customer_code="CUST-020",
                 incident="The routing application at the north depot, server CMRT-N01; the south depot works"),
            dict(role_ref("humongous_claims_certificate"), customer_code="CUST-013",
                 incident="The claims document management application on APP03; the certificate was renewed on the retired APP02"),
        ],
        "expected": "Three different incidents at three customers: same article (KB0133) and runbook (RB-005), separate tickets, never linked."}

    # ================================================================ similar issues, different resolutions
    def pair(symptom, a, b, evidence, open_a, open_b):
        return {"symptom": symptom, "articles": [a, b], "decided_by": evidence,
                "history": {a: [t["_key"]["spk_ticketnumber"] for t in history_for(a)],
                            b: [t["_key"]["spk_ticketnumber"] for t in history_for(b)]},
                "open": {a: [role_ref(r) for r in open_a], b: [role_ref(r) for r in open_b]}}
    scenarios["different_resolutions"] = {"pairs": [
        pair("A user's account locks several times a day", "KB0099", "KB0142",
             "The sign-in log: failures from the user's own device (saved password) or from unfamiliar addresses (password spray)",
             ["consolidated_dispatcher_lockout"], ["citypower_password_spray"]),
        pair("A printer shows offline", "KB0111", "KB0112",
             "The printer's address: changed after a network change, or unchanged and asleep",
             ["woodgrove_printer"], ["coho_printer_sleep"]),
        pair("A site cannot reach head office systems while the internet works", "KB0042", "KB0054",
             "The tunnel status: down after a peer address change, or up without traffic after a local network change",
             ["northwind_tunnel_down"], ["adventure_tunnel_no_traffic"]),
        pair("Nightly backups run into the working day", "KB0033", "KB0014",
             "The Backup Agent version: 5.x with vault encryption, or 4.x with a single upload stream",
             [], ["margies_backup_slow"]),
    ]}

    # ================================================================ escalation patterns
    escalated_history = [t for t in history if t["spk_isescalated"]]
    by_level = Counter(_label("spk_escalationlevel", t["spk_escalationlevel"]) for t in escalated_history)
    scenarios["escalation_patterns"] = {
        "history_total": len(escalated_history),
        "history_by_level": {lvl: by_level.get(lvl, 0) for lvl in CHOICES["spk_escalationlevel"]},
        "examples_by_level": {lvl: [t["_key"]["spk_ticketnumber"] for t in escalated_history
                                    if _label("spk_escalationlevel", t["spk_escalationlevel"]) == lvl][:3]
                              for lvl in CHOICES["spk_escalationlevel"]},
        "rules": [{k: v for k, v in rule.items() if k != "reason"} for rule in ESCALATION_RULES],
        "open_escalated": [dict(role_ref(number_to_role[t["_key"]["spk_ticketnumber"]]),
                                level=_label("spk_escalationlevel", t["spk_escalationlevel"]))
                           for t in open_records if t["spk_isescalated"]],
    }

    # ================================================================ technician patterns
    scenarios["technician_patterns"] = {
        "by_article": [{"article": kb_number, "technician": {"code": code, "name": tech_by_code[code]["name"]},
                        "history_tickets": len(history_for(kb_number)),
                        "all_assigned_to_technician": all(t["_lookups"]["spk_AssignedTechnicianId"][2] == code
                                                          for t in history_for(kb_number))}
                       for kb_number, code in TECHNICIAN_BY_ARTICLE.items()],
        "unavailable": [{"code": t["code"], "name": t["name"], "team": t["team"], "availability": t["availability"],
                         "open_tickets_assigned": [number_to_role[x["_key"]["spk_ticketnumber"]] for x in open_records
                                                   if (x["_lookups"].get("spk_AssignedTechnicianId") or [0, 0, None])[2] == t["code"]]}
                        for t in TECHNICIANS if not t["available"]],
        "teams": {team: [{"code": c, "name": tech_by_code[c]["name"], "tier": tech_by_code[c]["tier"]} for c in codes]
                  for team, codes in TEAMS.items()},
        "category_owners": CATEGORY_OWNERS,
    }

    # ================================================================ data protection
    scenarios["card_number_tickets"] = {
        "card_number": CARD_NUMBER, "keyword": "card number", "internal": True,
        "notes": [{"role": s["role"], "customer_code": s["customer"], "ticket": s["ticket"], "note": s["note"]}
                  for s in ctx["sensitive_notes"]],
        "guide_ticket": role_ref("trey_vault_quota"),
    }
    humongous_notes = [n for n in notes_by_ticket[role_numbers["humongous_claims_certificate"]] if n["spk_isinternal"]]
    scenarios["humongous_sensitive_notes"] = {
        "ticket": role_numbers["humongous_claims_certificate"],
        "invoice_dispute_note": next(n["_key"]["spk_notecode"] for n in humongous_notes if "invoice" in n["spk_body"]),
        "wrong_server_note": next(n["_key"]["spk_notecode"] for n in humongous_notes if "APP02" in n["spk_body"]),
        "never_in_a_customer_reply": ["the invoice dispute", "service credits", "APP02", "APP03",
                                      "the customer's own administrator"],
    }
    restricted_by_table = {name: sum(1 for r in rows if isinstance(r, dict) and r.get("_owner_team"))
                           for name, rows in data.items() if isinstance(rows, list)}
    scenarios["restricted_records"] = {
        "team": RESTRICTED_TEAM, "customers": sorted(RESTRICTED_CUSTOMERS),
        "records": sum(restricted_by_table.values()) - restricted_by_table.get("newincidents", 0),
        "by_table": {k: v for k, v in restricted_by_table.items() if v and k != "newincidents"},
        "open_tickets": [role_ref("lamna_new_starter"), role_ref("lamna_reimaged_laptop")],
    }

    # ================================================================ write targets
    scenarios["write_targets"] = {
        "approved_priority_change": dict(role_ref("contoso_qa_shared_mailbox"), from_priority="P4 Low", to_priority="P3 Medium",
                                         new_sla_target_hours=SLA_RESOLUTION_HOURS["Platinum"][3]),
        "declined_status_change": dict(role_ref("contoso_qa_shared_mailbox"), status_stays="New"),
        "reply_and_internal_note": role_ref("humongous_claims_certificate"),
        "tier1_versus_senior": dict(role_ref("woodgrove_slow_laptop"), from_priority="P3 Medium", to_priority="P2 High",
                                    new_sla_target_hours=SLA_RESOLUTION_HOURS["Platinum"][2]),
        "least_privilege_denied": dict(role_ref("lamna_reimaged_laptop"), owner_team=RESTRICTED_TEAM),
        "assign_to_available_network_technician": dict(role_ref("woodgrove_vpn_mortgage"), unavailable="TECH-02",
                                                       expected="TECH-08", also_acceptable=["TECH-14"]),
        "triage_and_assign": dict(role_ref("new_incident_adatum"), category="Backup and Recovery",
                                  subcategory="Storage quota", priority=3, technician="TECH-01"),
        "escalation_tool": dict(role_ref("new_incident_adatum"), level="Account Manager"),
        "end_to_end": dict(role_ref("new_incident_consolidated"), category="Line-of-Business App",
                           subcategory="Certificate", priority=2, technician="TECH-06", escalation_level="Vendor"),
    }

    # ================================================================ untriaged, documents, knowledge
    new_incident_roles = [t["role"] for t in sorted(NEW_INCIDENTS, key=lambda t: role_numbers[t["role"]])]
    scenarios["untriaged"] = {
        "seeded": [role_ref(r) for r in sorted(untriaged_roles, key=lambda r: role_numbers[r])],
        "new_incidents": [role_ref(r) for r in new_incident_roles],
        "view_count_after_new_incidents": len(untriaged_roles) + len(new_incident_roles),
    }
    doc_types = Counter(d["type"] for d in ctx["documents"])
    scenarios["customer_documents"] = {
        "by_type": dict(doc_types),
        "escalation_procedures": {d["customer"]: d["code"] for d in ctx["documents"] if d["type"] == "Escalation procedure"},
        "configuration_notes": {d["code"]: d["title"] for d in ctx["documents"] if d["type"] == "Configuration notes"},
        "support_policies": {d["customer"]: d["code"] for d in ctx["documents"] if d["type"] == "Support policy"},
        "labeled_document": {"customer_code": CONFIG_DOCUMENT["customer"], "filename": CONFIG_DOCUMENT["filename"],
                             "table": "annotation", "indexed": False},
    }
    statuses = Counter(kb["status"] for kb in KB_ARTICLES)
    scenarios["knowledge_base"] = {
        "articles": len(KB_ARTICLES), "by_status": dict(statuses),
        "draft": sorted(kb["number"] for kb in KB_ARTICLES if kb["status"] == "Draft"),
        "retired": sorted(kb["number"] for kb in KB_ARTICLES if kb["status"] == "Retired"),
        "related_articles": "Two to four per article; never a Retired or Draft article",
        "by_category": dict(Counter(kb["category"] for kb in KB_ARTICLES)),
    }

    # ================================================================ top-level manifest
    counts = {name: len(rows) for name, rows in data.items()
              if isinstance(rows, list) and name not in ("account_patches", "newincidents")}
    searchable = {
        "knowledge_articles": len(data["knowledgearticles"]),
        "customer_documents": len(data["customerdocuments"]),
        "runbooks": len(data["runbooks"]),
        "tickets": len(tickets),
        "customers": len(data["accounts"]),
        "sla_snapshot": 1,
    }
    searchable["total"] = sum(searchable.values())
    escalated_all = Counter(_label("spk_escalationlevel", t["spk_escalationlevel"]) for t in tickets if t["spk_isescalated"])
    return {
        "anchor": iso(anchor),
        # Deterministic on purpose: the files are a function of the seed and the anchor only.
        "generated_at": iso(anchor),
        "seed": seed,
        "data_version": "3.0",
        "counts": counts,
        "historical_tickets": len(history),
        "open_tickets": len(open_records),
        "new_incidents": [role_numbers[r] for r in new_incident_roles],
        "open_tickets_after_new_incidents": len(open_records) + len(NEW_INCIDENTS),
        "numbering": {"historical": [ctx["history_numbers"][0], ctx["history_numbers"][-1]],
                      "open": [min(role_numbers[r] for r in spec_by_role), max(role_numbers[r] for r in spec_by_role)],
                      "new_incidents": [role_numbers[r] for r in new_incident_roles]},
        "escalated_tickets": sum(escalated_all.values()),
        "escalated_by_level": {lvl: escalated_all.get(lvl, 0) for lvl in CHOICES["spk_escalationlevel"]},
        "restricted": {"team": RESTRICTED_TEAM, "customers": sorted(RESTRICTED_CUSTOMERS),
                       "records": scenarios["restricted_records"]["records"]},
        "searchable_documents": searchable,
        "not_indexed": ["ticket notes", "contact details", "the labeled configuration document (annotation)",
                        "the two new incidents"],
        "role_keys": dict(sorted(role_numbers.items(), key=lambda kv: kv[1])),
        "scenarios": scenarios,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", required=True, help="Output folder")
    parser.add_argument("--anchor", default="auto", help="SLA snapshot instant (ISO 8601 UTC) or 'auto'")
    parser.add_argument("--seed", type=int, default=20261001, help="Random seed (keep the default for lab parity)")
    args = parser.parse_args()

    if args.anchor == "auto":
        anchor = bizhours.snap_anchor(datetime.now(timezone.utc))
    else:
        anchor = datetime.fromisoformat(args.anchor.replace("Z", "+00:00")).astimezone(timezone.utc)
        if not bizhours.is_business_time(anchor) and anchor.hour != bizhours.DAY_END_HOUR:
            raise SystemExit("--anchor must fall inside business hours (Mon-Fri 08:00-18:00 UTC)")
    data = build(anchor, args.seed)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for name, rows in data.items():
        (out / f"{name}.json").write_text(json.dumps(rows, indent=1, ensure_ascii=True), encoding="utf-8", newline="\n")
    manifest = data["manifest"]
    print(json.dumps({k: v for k, v in manifest.items() if k not in ("scenarios", "role_keys")}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
