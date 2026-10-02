#!/usr/bin/env python3
"""Generate the Relecloud service desk seed dataset as Dataverse-shaped JSON.

Usage:
    python generate_seed.py --out data [--anchor auto|2026-10-05T14:00:00Z] [--seed 20261001]

The anchor is the SLA snapshot instant ("SLA Calculated On"). With --anchor auto it is
derived from the current time by bizhours.snap_anchor, so a fresh seed always looks recent.
For a given seed the content is identical for every anchor: ticket numbers, customers,
priorities, notes and counts never change, only the dates move (the history is generated
against REFERENCE_ANCHOR and shifted by whole weeks; setup/tests checks this across a year
of anchors). Re-running the generator and the loader re-anchors the dates.

Output files (one JSON array per table, records keyed by alternate key):
    businesscalendars.json slapolicies.json technicians.json accounts.json contacts.json
    customerprocedures.json runbooks.json knowledgearticles.json tickets.json ticketnotes.json
    annotations.json account_patches.json manifest.json
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
from datetime import datetime, timedelta, timezone
from pathlib import Path
from xml.sax.saxutils import escape

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bizhours  # noqa: E402
from catalog import (  # noqa: E402
    CATEGORY_TEAMS, CHOICES, CONTACT_ROLES, CUSTOMERS, FIRST_NAMES, KB_ARTICLES, LAST_NAMES,
    MSP_DOMAIN, PRIORITY_LABELS, PRIORITY_RULES, SLA_RESOLUTION_HOURS, SLA_RESPONSE_HOURS,
    TECHNICIANS,
)
from exercise_tickets import OPEN_TICKETS  # noqa: E402
from operations import (  # noqa: E402
    BILLING_RULE, CHANGE_RULES, CONFIG_DOCUMENT, ESCALATION_HOURS, ESCALATION_RULES,
    INCOMPLETE_TICKET, NEW_INCIDENTS, RUNBOOKS, SENSITIVE_NOTES, SPECIAL_PROCEDURES,
    TECHNICIAN_BY_ARTICLE,
)
from ticket_templates import APP_NAMES, PRINTER_NAMES, TEMPLATES, WEEKDAYS  # noqa: E402

HISTORY_SCALE = 1.6
FIRST_OPEN_NUMBER = 10471
# Historical tickets are generated against this fixed instant and then moved by a whole
# number of weeks to the real anchor, so every team gets the same history (ticket numbers,
# customers, priorities, notes) whenever its environment was seeded. Only the dates move.
REFERENCE_ANCHOR = datetime(2026, 10, 7, 14, 0, tzinfo=timezone.utc)
NO_SCALE = {"KB0058", "KB0028", "KB0067", "KB0047"}
PRODUCT_FIELD = {
    "Relecloud Backup Agent": "rba",
    "Relecloud Remote Access": "rra",
    "Relecloud Secure Gateway": "rsg",
    "Relecloud Endpoint Agent": "rea",
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


def build(anchor: datetime, seed: int) -> dict:
    rng = random.Random(seed)
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

    def add_procedure(customer_code: str, seq: int, proc_type: str, title: str, details: str, applies_to: str,
                      reviewed_days_ago: int) -> None:
        data["customerprocedures"].append(restricted({
            "_key": {"spk_procedurecode": f"{customer_code}-PR{seq}"},
            "spk_name": title,
            "spk_proceduretype": choice("spk_proceduretype", proc_type),
            "spk_details": details,
            "spk_appliesto": applies_to,
            "spk_lastreviewedon": (anchor - timedelta(days=reviewed_days_ago)).strftime("%Y-%m-%d"),
            "_lookups": {"spk_CustomerId": ["accounts", "spk_customercode", customer_code]},
        }, customer_code))

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
        })

    # ============================================================= tickets
    tickets: list[dict] = []
    notes: list[dict] = []
    note_seq: dict[str, int] = {}

    def fill(text: str, ctx: dict) -> str:
        return text.format(**ctx)

    def ticket_record(number, cust, contact_code, title, description, category, prio, status, tech_code,
                      product, version, affected, channel, opened, resolved, resolution, kb_number,
                      sla_target, sla_elapsed, sla_due, sla_status_label, sla_calc):
        rec = {
            "_key": {"spk_ticketnumber": number},
            "spk_name": title,
            "spk_description": description,
            "spk_category": choice("spk_category", category),
            "spk_priority": choice("spk_priority", PRIORITY_LABELS[prio]) if prio else None,
            "spk_status": choice("spk_ticketstatus", status),
            "spk_product": choice("spk_product", product),
            "spk_productversion": version or None,
            "spk_affectedusers": affected,
            "spk_channel": choice("spk_channel", channel),
            "spk_openedon": iso(opened),
            "spk_resolvedon": iso(resolved),
            "spk_resolutionsummary": resolution,
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

    def escalate(rec: dict, rule: dict, when: datetime) -> None:
        rec["spk_isescalated"] = True
        rec["spk_escalationlevel"] = choice("spk_escalationlevel", rule["level"])
        rec["spk_escalatedon"] = iso(when)
        rec["spk_escalationreason"] = rule["reason"]

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

    # ==== historical tickets from templates
    # Generated against REFERENCE_ANCHOR, never against the real anchor, so the random draws
    # (and therefore numbers, customers and notes) don't depend on when the seed runs. The
    # result moves by `shift`, a whole number of weeks, which keeps every weekday and every
    # business-hours figure intact and lands the history just before the real anchor. Every
    # historical ticket opens before the oldest open ticket, so ticket numbers stay
    # chronological across the two ranges. The technician and escalation patterns from
    # operations.py are applied after each draw and use no random numbers, so they never
    # change the sequence.
    ref = REFERENCE_ANCHOR
    shift = timedelta(weeks=math.floor((anchor - ref) / timedelta(weeks=1)))
    tuesdays = patch_tuesdays(ref, 270)
    open_specs = OPEN_TICKETS + [INCOMPLETE_TICKET]
    oldest_open = bizhours.subtract_business_hours(ref, max(t["elapsed_bh"] for t in open_specs))
    history_cutoff = oldest_open - timedelta(hours=1)
    history = []
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
            history.append((opened, spec, kb, cust, prio, affected))

    history.sort(key=lambda h: h[0])
    if len(history) > FIRST_OPEN_NUMBER - 10001:
        raise SystemExit(f"Too many historical tickets ({len(history)}) for the reserved number range")

    first_history_ticket: dict[str, tuple[str, datetime, datetime]] = {}
    for idx, (opened, spec, kb, cust, prio, affected) in enumerate(history):
        number = f"TCK-{10001 + idx}"
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
        title = fill(rng.choice(spec["titles"]), ctx)
        description = fill(rng.choice(spec["descriptions"]), ctx)
        resolution = fill(rng.choice(spec["resolution"]), ctx)
        category = kb["category"]
        product = kb["product"]
        field = PRODUCT_FIELD.get(product)
        version = VERSION_AT_TIME.get(kb["number"]) or (cust[field] if field else None)
        tech_code = rng.choice(CATEGORY_TEAMS[category])
        tech_code = TECHNICIAN_BY_ARTICLE.get(kb["number"], tech_code)
        target = float(SLA_RESOLUTION_HOURS[cust["tier"]][prio])
        breached = rng.random() < 0.12
        factor = rng.uniform(1.05, 1.6) if breached else rng.uniform(0.15, 0.95)
        elapsed_plan = max(0.5, round(target * factor * 2) / 2)
        resolved = bizhours.add_business_hours(opened, elapsed_plan)
        if resolved >= ref - timedelta(hours=4):
            resolved = bizhours.subtract_business_hours(ref, 4)
        elapsed = bizhours.business_hours_between(opened, resolved)
        due = bizhours.add_business_hours(opened, target)
        sla_label = bizhours.sla_status(target, elapsed, resolved=True)
        # Everything above is in the reference frame; move it to the real anchor.
        opened_at, resolved_at, due_at = opened + shift, resolved + shift, due + shift
        status = "Closed" if resolved_at < anchor - timedelta(days=3) else "Resolved"
        rec = ticket_record(number, cust, contact["code"], title, description, category, prio, status,
                            tech_code, product, version, affected, spec.get("channel", "Email"), opened_at,
                            resolved_at, resolution, kb["number"], target, elapsed, due_at, sla_label,
                            resolved_at)
        rule = escalation_for(cust["code"], category, kb["number"], prio)
        if rule:
            escalate(rec, rule, bizhours.add_business_hours(opened, min(1.0, elapsed / 2)) + shift)
        tickets.append(rec)
        first_history_ticket.setdefault(cust["code"], (number, opened_at, resolved_at))
        tech_name = tech_by_code[tech_code]["name"]
        ack_time = bizhours.add_business_hours(opened, min(0.5, elapsed / 3)) + shift
        add_note(number, False, tech_name,
                 f"Hi {contact['first']}, thanks for reporting this. We are looking into it now and will keep you updated on this ticket.",
                 ack_time, cust["code"])
        if rng.random() < 0.65:
            add_note(number, True, tech_name, rng.choice(spec["internal"]),
                     bizhours.add_business_hours(opened, elapsed / 2) + shift, cust["code"])
        if rule:
            add_note(number, True, tech_name, f"Escalated ({rule['level']}): {rule['reason']}",
                     bizhours.add_business_hours(opened, min(1.0, elapsed / 2)) + shift, cust["code"])
        add_note(number, False, tech_name,
                 f"Hi {contact['first']}, this is now resolved. {resolution.split('. ')[0]}. Please reply if anything else comes up.",
                 resolved_at, cust["code"])

    # ==== hand-authored open tickets, plus the seeded ticket with too little information
    open_opened: dict[str, datetime] = {}
    for t in open_specs:
        cust = customer_by_code[t["customer"]]
        contact = contacts_by_customer[cust["code"]][t["contact"]]
        opened = bizhours.subtract_business_hours(anchor, t["elapsed_bh"])
        open_opened[t["number"]] = opened
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
        rec = ticket_record(t["number"], cust, contact["code"], t["title"], t["description"],
                            t["category"], prio, t["status"], t["technician"], product, version,
                            t["affected"], t["channel"], opened, None, None, t["kb"],
                            target, elapsed, due, label, calc)
        if prio == 1:
            escalate(rec, ESCALATION_RULES[0], bizhours.add_business_hours(opened, 0.5))
        tickets.append(rec)
        for is_internal, author, body, after in t["notes"]:
            when = bizhours.add_business_hours(opened, after)
            if when > anchor:
                raise SystemExit(f"A note on {t['number']} would be after the anchor")
            add_note(t["number"], is_internal, author, body, when, cust["code"])

    # ==== sensitive test values for the data protection exercise
    for s in SENSITIVE_NOTES:
        if "ticket" in s:
            number = s["ticket"]
            when = bizhours.add_business_hours(open_opened[number], s["after_bh"])
            customer_code = next(t["customer"] for t in open_specs if t["number"] == number)
        else:
            customer_code = s["history_customer"]
            number, opened_at, resolved_at = first_history_ticket[customer_code]
            when = opened_at + (resolved_at - opened_at) / 3
        add_note(number, s["internal"], s["author"], s["body"], when, customer_code)

    data["tickets"] = tickets
    data["ticketnotes"] = notes

    # ============================================================= labelled configuration document
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
    for t in NEW_INCIDENTS:
        cust = customer_by_code[t["customer"]]
        contact = contacts_by_customer[cust["code"]][t["contact"]]
        opened = bizhours.subtract_business_hours(anchor, t["elapsed_bh"])
        data["newincidents"].append(ticket_record(t["number"], cust, contact["code"], t["title"], t["description"],
                                                  None, None, "New", None, None, None, None, t["channel"], opened,
                                                  None, None, None, None, None, None, None, None))

    open_statuses = {CHOICES["spk_ticketstatus"][s] for s in ("New", "In Progress", "Waiting on Customer")}
    seeded_open = sum(1 for r in tickets if r["spk_status"] in open_statuses)
    data["manifest"] = {
        "anchor": iso(anchor),
        "generated_at": iso(datetime.now(timezone.utc)),
        "seed": seed,
        "counts": {name: len(rows) for name, rows in data.items()
                   if isinstance(rows, list) and name not in ("account_patches", "newincidents")},
        "open_tickets": seeded_open,
        "new_incidents": [t["number"] for t in NEW_INCIDENTS],
        "open_tickets_after_new_incidents": seeded_open + len(NEW_INCIDENTS),
        "escalated_tickets": sum(1 for r in tickets if r["spk_isescalated"]),
        "restricted": {"team": RESTRICTED_TEAM, "customers": sorted(RESTRICTED_CUSTOMERS),
                       "records": sum(1 for rows in data.values() if isinstance(rows, list)
                                      for r in rows if isinstance(r, dict) and r.get("_owner_team"))},
        "searchable_documents": {
            "knowledge_articles": len(data["knowledgearticles"]),
            "runbooks": len(data["runbooks"]),
            "tickets": len(tickets),
            "customers": len(data["accounts"]),
            "sla_snapshot": 1,
            "total": len(data["knowledgearticles"]) + len(data["runbooks"]) + len(tickets) + len(data["accounts"]) + 1,
        },
    }
    return data


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
        (out / f"{name}.json").write_text(json.dumps(rows, indent=1, ensure_ascii=True), encoding="utf-8")
    print(json.dumps(data["manifest"], indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
