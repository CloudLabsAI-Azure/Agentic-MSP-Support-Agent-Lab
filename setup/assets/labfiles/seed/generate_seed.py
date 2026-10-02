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
    knowledgearticles.json tickets.json ticketnotes.json account_patches.json manifest.json

Record conventions understood by load_seed.py:
    "_key":     {alternate key column: value}
    "_lookups": {navigation property: [entity set, alternate key column, value]}
    every other key is a Dataverse column logical name with its value.
"""
from __future__ import annotations

import argparse
import json
import math
import random
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bizhours  # noqa: E402
from catalog import (  # noqa: E402
    CATEGORY_TEAMS, CHOICES, CONTACT_ROLES, CUSTOMERS, FIRST_NAMES, KB_ARTICLES, LAST_NAMES,
    MSP_DOMAIN, PRIORITY_LABELS, PRIORITY_RULES, SLA_RESOLUTION_HOURS, SLA_RESPONSE_HOURS,
    TECHNICIANS,
)
from exercise_tickets import OPEN_TICKETS  # noqa: E402
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


def build(anchor: datetime, seed: int) -> dict:
    rng = random.Random(seed)
    data: dict[str, list] = {}

    # ------------------------------------------------------------- calendar + SLA policies
    data["businesscalendars"] = [{
        "_key": {"msp_calendarcode": "STD"},
        "msp_name": bizhours.CALENDAR_NAME,
        "msp_description": bizhours.CALENDAR_DESCRIPTION,
        "msp_timezone": "UTC",
        "msp_workdays": "Monday to Friday",
        "msp_daystart": "08:00",
        "msp_dayend": "18:00",
        "msp_hoursperday": float(bizhours.HOURS_PER_DAY),
        "msp_holidays": "None configured for the current period.",
    }]
    data["slapolicies"] = []
    for tier, targets in SLA_RESOLUTION_HOURS.items():
        for prio, hours in targets.items():
            data["slapolicies"].append({
                "_key": {"msp_policycode": f"{tier[:4].upper()}-P{prio}"},
                "msp_name": f"{tier} {PRIORITY_LABELS[prio]}",
                "msp_slatier": choice("msp_slatier", tier),
                "msp_priority": choice("msp_priority", PRIORITY_LABELS[prio]),
                "msp_responsehours": float(SLA_RESPONSE_HOURS[tier][prio]),
                "msp_resolutionhours": float(hours),
                "msp_description": f"{tier} customers, {PRIORITY_LABELS[prio]}: first response within "
                                   f"{SLA_RESPONSE_HOURS[tier][prio]} business hours, resolution within {hours} business hours. "
                                   + PRIORITY_RULES,
                "_lookups": {"msp_CalendarId": ["msp_businesscalendars", "msp_calendarcode", "STD"]},
            })

    # ------------------------------------------------------------- technicians
    data["technicians"] = [{
        "_key": {"msp_techniciancode": t["code"]},
        "msp_name": t["name"],
        "msp_email": t["name"].lower().replace(" ", ".") + "@" + MSP_DOMAIN,
        "msp_team": choice("msp_technicianteam", t["team"]),
        "msp_tier": choice("msp_techniciantier", t["tier"]),
        "msp_isavailable": t["available"],
        "msp_skills": t["skills"],
    } for t in TECHNICIANS]
    tech_by_code = {t["code"]: t for t in TECHNICIANS}

    # ------------------------------------------------------------- customers + contacts
    data["accounts"], data["contacts"], data["account_patches"] = [], [], []
    contacts_by_customer: dict[str, list[dict]] = {}
    i = 0
    for c in CUSTOMERS:
        data["accounts"].append({
            "_key": {"msp_customercode": c["code"]},
            "name": c["name"],
            "msp_industry": c["industry"],
            "address1_city": c["city"],
            "msp_slatier": choice("msp_slatier", c["tier"]),
            "msp_contracttype": choice("msp_contracttype", c["contract"]),
            "msp_seatcount": c["seats"],
            "msp_sitecount": c["sites"],
            "msp_backupagentversion": c["rba"],
            "msp_remoteaccessversion": c["rra"],
            "msp_gatewayfirmware": c["rsg"],
            "msp_endpointagentversion": c["rea"],
            "msp_accountmanager": c["account_manager"],
            "websiteurl": f"https://www.{c['domain']}",
            "description": c["profile"],
        })
        contacts_by_customer[c["code"]] = []
        for slot, (job, role) in enumerate(CONTACT_ROLES):
            first = FIRST_NAMES[(i * 7) % len(FIRST_NAMES)]
            last = LAST_NAMES[(i * 11) % len(LAST_NAMES)]
            code = f"{c['code']}-C{slot + 1}"
            rec = {
                "_key": {"msp_contactcode": code},
                "firstname": first,
                "lastname": last,
                "jobtitle": job,
                "msp_contactrole": role,
                "emailaddress1": f"{first.lower()}.{last.lower()}@{c['domain']}",
                "telephone1": f"+1 425 555 01{i:02d}",
                "mobilephone": f"+1 206 555 01{i:02d}",
                "_lookups": {"parentcustomerid_account": ["accounts", "msp_customercode", c["code"]]},
            }
            data["contacts"].append(rec)
            contacts_by_customer[c["code"]].append({"code": code, "first": first, "last": last})
            i += 1
        data["account_patches"].append({
            "_key": {"msp_customercode": c["code"]},
            "_lookups": {"primarycontactid": ["contacts", "msp_contactcode", f"{c['code']}-C1"]},
        })
    customer_by_code = {c["code"]: c for c in CUSTOMERS}

    # ------------------------------------------------------------- knowledge articles
    data["knowledgearticles"] = []
    kb_by_number = {}
    for kb in KB_ARTICLES:
        applies, versions_text, tiers_text, contracts_text = applies_to_text(kb)
        kb_by_number[kb["number"]] = kb
        data["knowledgearticles"].append({
            "_key": {"msp_articlenumber": kb["number"]},
            "msp_name": kb["title"],
            "msp_category": choice("msp_category", kb["category"]),
            "msp_product": choice("msp_product", kb["product"]),
            "msp_symptom": kb["symptom"],
            "msp_cause": kb["cause"],
            "msp_resolution": kb["resolution"],
            "msp_appliesto": applies,
            "msp_appliestoversions": versions_text,
            "msp_appliestotiers": tiers_text,
            "msp_appliestocontracts": contracts_text,
            "msp_kbstatus": choice("msp_kbstatus", kb["status"]),
            "msp_lastreviewedon": (anchor - timedelta(days=kb["reviewed_days_ago"])).strftime("%Y-%m-%d"),
            "msp_keywords": kb["keywords"],
        })

    # ------------------------------------------------------------- tickets
    tickets: list[dict] = []
    notes: list[dict] = []

    def fill(text: str, ctx: dict) -> str:
        return text.format(**ctx)

    def ticket_record(number, cust, contact_code, title, description, category, prio, status, tech_code,
                      product, version, affected, channel, opened, resolved, resolution, kb_number,
                      sla_target, sla_elapsed, sla_due, sla_status_label, sla_calc):
        rec = {
            "_key": {"msp_ticketnumber": number},
            "msp_name": title,
            "msp_description": description,
            "msp_category": choice("msp_category", category),
            "msp_priority": choice("msp_priority", PRIORITY_LABELS[prio]) if prio else None,
            "msp_status": choice("msp_ticketstatus", status),
            "msp_product": choice("msp_product", product),
            "msp_productversion": version or None,
            "msp_affectedusers": affected,
            "msp_channel": choice("msp_channel", channel),
            "msp_openedon": iso(opened),
            "msp_resolvedon": iso(resolved),
            "msp_resolutionsummary": resolution,
            "msp_slatargethours": sla_target,
            "msp_slaelapsedhours": sla_elapsed,
            "msp_slaremaininghours": None if sla_target is None else round(sla_target - sla_elapsed, 2),
            "msp_sladueon": iso(sla_due),
            "msp_slastatus": choice("msp_slastatus", sla_status_label),
            "msp_slacalculatedon": iso(sla_calc),
            "_lookups": {
                "msp_CustomerId": ["accounts", "msp_customercode", cust["code"]],
                "msp_ContactId": ["contacts", "msp_contactcode", contact_code],
            },
        }
        if tech_code:
            rec["_lookups"]["msp_AssignedTechnicianId"] = ["msp_technicians", "msp_techniciancode", tech_code]
        if kb_number:
            rec["_lookups"]["msp_RelatedArticleId"] = ["msp_knowledgearticles", "msp_articlenumber", kb_number]
        return rec

    def add_note(ticket_number, seq, is_internal, author, body, when):
        notes.append({
            "_key": {"msp_notecode": f"{ticket_number}-N{seq}"},
            "msp_name": (("Internal: " if is_internal else "Reply: ") + body)[:95],
            "msp_body": body,
            "msp_isinternal": is_internal,
            "msp_author": author,
            "msp_notedon": iso(when),
            "_lookups": {"msp_TicketId": ["msp_tickets", "msp_ticketnumber", ticket_number]},
        })

    # ---- historical tickets from templates
    # Generated against REFERENCE_ANCHOR, never against the real anchor, so the random draws
    # (and therefore numbers, customers and notes) don't depend on when the seed runs. The
    # result moves by `shift`, a whole number of weeks, which keeps every weekday and every
    # business-hours figure intact and lands the history just before the real anchor. Every
    # historical ticket opens before the oldest open ticket, so ticket numbers stay
    # chronological across the two ranges.
    ref = REFERENCE_ANCHOR
    shift = timedelta(weeks=math.floor((anchor - ref) / timedelta(weeks=1)))
    tuesdays = patch_tuesdays(ref, 270)
    oldest_open = bizhours.subtract_business_hours(ref, max(t["elapsed_bh"] for t in OPEN_TICKETS))
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
        tickets.append(ticket_record(number, cust, contact["code"], title, description, category, prio, status,
                                     tech_code, product, version, affected, spec.get("channel", "Email"), opened_at,
                                     resolved_at, resolution, kb["number"], target, elapsed, due_at, sla_label,
                                     resolved_at))
        tech_name = tech_by_code[tech_code]["name"]
        ack_time = bizhours.add_business_hours(opened, min(0.5, elapsed / 3)) + shift
        add_note(number, 1, False, tech_name,
                 f"Hi {contact['first']}, thanks for reporting this. We are looking into it now and will keep you updated on this ticket.",
                 ack_time)
        seq = 2
        if rng.random() < 0.65:
            add_note(number, seq, True, tech_name, rng.choice(spec["internal"]),
                     bizhours.add_business_hours(opened, elapsed / 2) + shift)
            seq += 1
        add_note(number, seq, False, tech_name,
                 f"Hi {contact['first']}, this is now resolved. {resolution.split('. ')[0]}. Please reply if anything else comes up.",
                 resolved_at)

    # ---- hand-authored open tickets
    for t in OPEN_TICKETS:
        cust = customer_by_code[t["customer"]]
        contact = contacts_by_customer[cust["code"]][t["contact"]]
        opened = bizhours.subtract_business_hours(anchor, t["elapsed_bh"])
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
        tickets.append(ticket_record(t["number"], cust, contact["code"], t["title"], t["description"],
                                     t["category"], prio, t["status"], t["technician"], product, version,
                                     t["affected"], t["channel"], opened, None, None, t["kb"],
                                     target, elapsed, due, label, calc))
        for seq, (is_internal, author, body, after) in enumerate(t["notes"], start=1):
            when = bizhours.add_business_hours(opened, after)
            if when > anchor:
                raise SystemExit(f"Note {t['number']}-N{seq} would be after the anchor")
            add_note(t["number"], seq, is_internal, author, body, when)

    data["tickets"] = tickets
    data["ticketnotes"] = notes
    open_statuses = {CHOICES["msp_ticketstatus"][s] for s in ("New", "In Progress", "Waiting on Customer")}
    data["manifest"] = {
        "anchor": iso(anchor),
        "generated_at": iso(datetime.now(timezone.utc)),
        "seed": seed,
        "counts": {name: len(rows) for name, rows in data.items() if isinstance(rows, list) and name != "account_patches"},
        "open_tickets": sum(1 for r in tickets if r["msp_status"] in open_statuses),
        "searchable_documents": {
            "knowledge_articles": len(data["knowledgearticles"]),
            "tickets": len(tickets),
            "customers": len(data["accounts"]),
            "sla_snapshot": 1,
            "total": len(data["knowledgearticles"]) + len(tickets) + len(data["accounts"]) + 1,
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
