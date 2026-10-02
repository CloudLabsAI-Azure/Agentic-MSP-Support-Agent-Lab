#!/usr/bin/env python3
"""Load the generated seed dataset into a Dataverse environment through the Web API.

Usage:
    python load_seed.py --url https://mspdesk123456.crm4.dynamics.com --data data [--reset] [--workers 8]
    python load_seed.py --url ... --data data --only newincidents
    python load_seed.py --url ... --data data --label-id <guid> --label-name Confidential --tenant-id <guid>

Authentication: the access token in the MSPLAB_DATAVERSE_TOKEN environment variable when it
is set (Provision-ServiceDesk.ps1 passes the team user's token this way), otherwise a token
from the Azure CLI session of the signed-in user (az account get-access-token --resource <url>).

Every record is upserted with PATCH on its alternate key, so a re-run updates rather than
duplicates. --reset first deletes every Service Desk record (notes, tickets, procedures,
runbooks, articles, the configuration document, seeded contacts and accounts, technicians,
SLA policies, calendars); use it to re-anchor the data before an event.

The two new incidents (newincidents.json) are not loaded by default: provisioning loads them
with --only newincidents AFTER it exports the search content, so they are never indexed.
Records that carry "_owner_team" are assigned to that Dataverse team (the restricted business
unit). --label-id stamps a Microsoft Purview sensitivity label on the configuration document
before it is uploaded.

The loader finishes by counting records per table and exits with status 1 if any count
differs from manifest.json. Only the Python standard library is used.
"""
from __future__ import annotations

import argparse
import base64
import io
import json
import os

import subprocess

import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zipfile
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from xml.sax.saxutils import escape

# (data file, entity set, alternate key column, filter that selects seeded rows for reset/count)
LOAD_ORDER = [
    ("businesscalendars", "spk_businesscalendars", "spk_calendarcode", "spk_calendarcode ne null"),
    ("slapolicies", "spk_slapolicies", "spk_policycode", "spk_policycode ne null"),
    ("technicians", "spk_technicians", "spk_techniciancode", "spk_techniciancode ne null"),
    ("accounts", "accounts", "spk_customercode", "spk_customercode ne null"),
    ("contacts", "contacts", "spk_contactcode", "spk_contactcode ne null"),
    ("account_patches", "accounts", "spk_customercode", None),
    ("customerprocedures", "spk_customerprocedures", "spk_procedurecode", "spk_procedurecode ne null"),
    ("runbooks", "spk_runbooks", "spk_runbookcode", "spk_runbookcode ne null"),
    ("knowledgearticles", "spk_knowledgearticles", "spk_articlenumber", "spk_articlenumber ne null"),
    ("tickets", "spk_tickets", "spk_ticketnumber", "spk_ticketnumber ne null"),
    ("ticketnotes", "spk_ticketnotes", "spk_notecode", "spk_notecode ne null"),
]
PRIMARY_KEYS = {"spk_businesscalendars": "spk_businesscalendarid", "spk_slapolicies": "spk_slapolicyid",
                "spk_technicians": "spk_technicianid", "accounts": "accountid", "contacts": "contactid",
                "spk_customerprocedures": "spk_customerprocedureid", "spk_runbooks": "spk_runbookid",
                "spk_knowledgearticles": "spk_knowledgearticleid", "spk_tickets": "spk_ticketid",
                "spk_ticketnotes": "spk_ticketnoteid", "annotations": "annotationid", "teams": "teamid"}
MSIP_FMTID = "{D5CDD505-2E9C-101B-9397-08002B2CF9AE}"


class Dataverse:
    def __init__(self, url: str):
        self.url = url.rstrip("/")
        self.api = f"{self.url}/api/data/v9.2/"
        self._token = ""
        self._expires = 0.0
        self._lock = threading.Lock()

    def token(self) -> str:
        supplied = os.environ.get("MSPLAB_DATAVERSE_TOKEN", "").strip()
        if supplied:
            return supplied
        with self._lock:
            if time.time() > self._expires:
                out = subprocess.run(f'az account get-access-token --resource "{self.url}" --query accessToken --output tsv',
                                     shell=True, capture_output=True, text=True)
                if out.returncode or not out.stdout.strip():
                    raise SystemExit(f"Could not get a Dataverse token. Run 'az login' first. {out.stderr.strip()}")
                self._token, self._expires = out.stdout.strip(), time.time() + 40 * 60
            return self._token

    def request(self, method: str, path: str, body: dict | None = None, extra: dict | None = None) -> tuple[int, dict, dict]:
        data = json.dumps(body).encode("utf-8") if body is not None else None
        for attempt in range(1, 7):
            req = urllib.request.Request(self.api + path, data=data, method=method)
            req.add_header("Authorization", f"Bearer {self.token()}")
            req.add_header("Accept", "application/json")
            req.add_header("OData-MaxVersion", "4.0")
            req.add_header("OData-Version", "4.0")
            if data is not None:
                req.add_header("Content-Type", "application/json; charset=utf-8")
            for k, v in (extra or {}).items():
                req.add_header(k, v)
            try:
                with urllib.request.urlopen(req, timeout=120) as resp:
                    raw = resp.read()
                    return resp.status, (json.loads(raw) if raw else {}), dict(resp.headers)
            except urllib.error.HTTPError as err:
                raw = err.read()
                if err.code == 429 or err.code >= 500:
                    wait = float(err.headers.get("Retry-After") or 3 * attempt)
                    time.sleep(min(wait, 60))
                    continue
                try:
                    payload = json.loads(raw) if raw else {}
                except ValueError:
                    payload = {"error": {"message": raw.decode("utf-8", "replace")[:500]}}
                return err.code, payload, dict(err.headers)
            except (urllib.error.URLError, TimeoutError):
                time.sleep(3 * attempt)
        return 599, {"error": {"message": "retries exhausted"}}, {}


def key_path(entity_set: str, key_col: str, value: str) -> str:
    return f"{entity_set}({key_col}='{value.replace(chr(39), chr(39) * 2)}')"


class Owners:
    """Resolves "_owner_team" names to team IDs once."""

    def __init__(self, dv: Dataverse):
        self.dv = dv
        self.cache: dict[str, str | None] = {}
        self.lock = threading.Lock()

    def bind(self, name: str) -> str | None:
        with self.lock:
            if name not in self.cache:
                filt = urllib.parse.quote(f"name eq '{name}'")
                status, payload, _ = self.dv.request("GET", f"teams?$select=teamid&$filter={filt}")
                rows = payload.get("value", []) if status < 400 else []
                self.cache[name] = rows[0]["teamid"] if rows else None
                if not rows:
                    print(f"  warning: team '{name}' not found; records keep their default owner")
            team_id = self.cache[name]
        return f"/teams({team_id})" if team_id else None


def to_body(record: dict, owners: Owners) -> dict:
    body = {k: v for k, v in record.items() if not k.startswith("_")}
    for nav, (entity_set, key_col, value) in record.get("_lookups", {}).items():
        body[f"{nav}@odata.bind"] = "/" + key_path(entity_set, key_col, value)
    if record.get("_owner_team"):
        owner = owners.bind(record["_owner_team"])
        if owner:
            body["ownerid@odata.bind"] = owner
    return body


def upsert_all(dv: Dataverse, owners: Owners, records: list[dict], entity_set: str, key_col: str, workers: int) -> list[str]:
    errors: list[str] = []

    def one(record: dict) -> None:
        key_value = record["_key"][key_col]
        status, payload, _ = dv.request("PATCH", key_path(entity_set, key_col, key_value), to_body(record, owners))
        if status >= 400:
            errors.append(f"{entity_set} {key_value}: HTTP {status} {payload.get('error', {}).get('message', '')[:300]}")

    with ThreadPoolExecutor(max_workers=workers) as pool:
        list(pool.map(one, records))
    return errors


def stamp_label(docx: bytes, label_id: str, label_name: str, tenant_id: str) -> bytes:
    """Record a Microsoft Purview sensitivity label (no encryption) in the document's custom
    properties, the way Office records labels it applies."""
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    values = [("Enabled", "true"), ("SetDate", stamp), ("Method", "Privileged"), ("Name", label_name),
              ("SiteId", tenant_id), ("ActionId", str(uuid.uuid4())), ("ContentBits", "0")]
    props = "".join(
        f'<property fmtid="{MSIP_FMTID}" pid="{pid}" name="MSIP_Label_{label_id}_{name}"><vt:lpwstr>{escape(value)}</vt:lpwstr></property>'
        for pid, (name, value) in enumerate(values, start=2))
    custom = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/custom-properties" '
              f'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">{props}</Properties>')
    src = zipfile.ZipFile(io.BytesIO(docx))
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as dst:
        for info in src.infolist():
            content = custom.encode("utf-8") if info.filename == "docProps/custom.xml" else src.read(info.filename)
            dst.writestr(info, content)
    return out.getvalue()


def load_annotations(dv: Dataverse, records: list[dict], label: dict | None) -> list[str]:
    errors = []
    for record in records:
        body = {k: v for k, v in record.items() if not k.startswith("_")}
        if label and body.get("documentbody"):
            docx = stamp_label(base64.b64decode(body["documentbody"]), label["id"], label["name"], label["tenant"])
            body["documentbody"] = base64.b64encode(docx).decode("ascii")
            body["notetext"] = f"{body.get('notetext', '')} Sensitivity label: {label['name']}.".strip()
        for nav, (entity_set, key_col, value) in record.get("_lookups", {}).items():
            body[f"{nav}@odata.bind"] = "/" + key_path(entity_set, key_col, value)
        filt = urllib.parse.quote(f"filename eq '{record['_match']['filename']}'")
        status, payload, _ = dv.request("GET", f"annotations?$select=annotationid&$filter={filt}")
        existing = payload.get("value", []) if status < 400 else []
        if existing:
            status, payload, _ = dv.request("PATCH", f"annotations({existing[0]['annotationid']})", body)
        else:
            status, payload, _ = dv.request("POST", "annotations", body)
        if status >= 400:
            errors.append(f"annotations {record['_match']['filename']}: HTTP {status} {payload.get('error', {}).get('message', '')[:300]}")
    return errors


def ids_matching(dv: Dataverse, entity_set: str, filt: str) -> list[str]:
    pk = PRIMARY_KEYS[entity_set]
    path = f"{entity_set}?$select={pk}&$filter={urllib.parse.quote(filt)}"
    ids: list[str] = []
    while path:
        status, payload, _ = dv.request("GET", path, extra={"Prefer": "odata.maxpagesize=5000"})
        if status >= 400:
            raise SystemExit(f"Query failed on {entity_set}: {payload}")
        ids += [row[pk] for row in payload.get("value", [])]
        nxt = payload.get("@odata.nextLink")
        path = nxt.replace(dv.api, "") if nxt else ""
    return ids


def reset(dv: Dataverse, workers: int, annotation_names: list[str]) -> None:
    for name in annotation_names:
        for annotation_id in ids_matching(dv, "annotations", f"filename eq '{name}'"):
            dv.request("DELETE", f"annotations({annotation_id})")
    for _, entity_set, _, filt in reversed(LOAD_ORDER):
        if not filt:
            continue
        if entity_set == "accounts":
            # Detach primary contacts first so accounts and contacts delete cleanly.
            for account_id in ids_matching(dv, "accounts", filt):
                dv.request("DELETE", f"accounts({account_id})/primarycontactid/$ref")
        ids = ids_matching(dv, entity_set, filt)
        with ThreadPoolExecutor(max_workers=workers) as pool:
            list(pool.map(lambda i: dv.request("DELETE", f"{entity_set}({i})"), ids))
        print(f"  deleted {len(ids):5d} from {entity_set}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", required=True)
    parser.add_argument("--data", default=str(Path(__file__).resolve().parent / "data"))
    parser.add_argument("--reset", action="store_true")
    parser.add_argument("--only", choices=["newincidents"], help="Load only the new incidents (after the search export)")
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--label-id", default="", help="Purview sensitivity label ID for the configuration document")
    parser.add_argument("--label-name", default="Confidential")
    parser.add_argument("--tenant-id", default="")
    args = parser.parse_args()

    dv = Dataverse(args.url)
    owners = Owners(dv)
    data = Path(args.data)
    manifest = json.loads((data / "manifest.json").read_text(encoding="utf-8"))
    new_numbers = manifest.get("new_incidents", [])
    print(f"Seed anchor (SLA Calculated On): {manifest['anchor']}")

    all_errors: list[str] = []
    if args.only == "newincidents":
        records = json.loads((data / "newincidents.json").read_text(encoding="utf-8"))
        all_errors += upsert_all(dv, owners, records, "spk_tickets", "spk_ticketnumber", args.workers)
        found = [n for n in new_numbers if ids_matching(dv, "spk_tickets", f"spk_ticketnumber eq '{n}'")]
        print(f"  new incidents loaded: {', '.join(found) or 'none'}")
        missing = sorted(set(new_numbers) - set(found))
        for line in all_errors:
            print("  error:", line)
        return 1 if (all_errors or missing) else 0

    annotations = json.loads((data / "annotations.json").read_text(encoding="utf-8"))
    if args.reset:
        print("Removing existing Service Desk records")
        reset(dv, args.workers, [a["_match"]["filename"] for a in annotations])

    for name, entity_set, key_col, _ in LOAD_ORDER:
        records = json.loads((data / f"{name}.json").read_text(encoding="utf-8"))
        started = time.time()
        errors = upsert_all(dv, owners, records, entity_set, key_col, args.workers)
        all_errors += errors
        print(f"  {name:18s} {len(records):5d} records in {time.time() - started:5.1f} s, {len(errors)} errors")
    label = {"id": args.label_id, "name": args.label_name, "tenant": args.tenant_id} if args.label_id else None
    errors = load_annotations(dv, annotations, label)
    all_errors += errors
    print(f"  {'annotations':18s} {len(annotations):5d} records, {len(errors)} errors"
          f"{', label ' + args.label_name if label else ', no sensitivity label (set --label-id)'}")

    print("Verifying counts")
    mismatches = []
    # Notes the agent writes during the lab use codes like TCK-10507-A1; seeded notes end -N<n>.
    # The new incidents are loaded separately. Count only seeded rows, so re-running the
    # loader during or after the lab still verifies.
    excluded = "".join(f" and spk_ticketnumber ne '{n}'" for n in new_numbers)
    count_filters = {"ticketnotes": "contains(spk_notecode,'-N')", "tickets": "spk_ticketnumber ne null" + excluded}
    for name, entity_set, _, filt in LOAD_ORDER:
        if not filt:
            continue
        filt = count_filters.get(name, filt)
        expected = manifest["counts"][name]
        actual = len(ids_matching(dv, entity_set, filt))
        flag = "ok" if actual == expected else "MISMATCH"
        print(f"  {entity_set:24s} expected {expected:5d} actual {actual:5d} {flag}")
        if actual != expected:
            mismatches.append(entity_set)

    summary = {"anchor": manifest["anchor"], "errors": all_errors[:50], "error_count": len(all_errors),
               "mismatches": mismatches, "label_applied": bool(label),
               "loaded_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    (data / "load-summary.json").write_text(json.dumps(summary, indent=1), encoding="utf-8")
    for line in all_errors[:20]:
        print("  error:", line)
    return 1 if (all_errors or mismatches) else 0


if __name__ == "__main__":
    raise SystemExit(main())
