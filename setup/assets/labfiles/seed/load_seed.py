#!/usr/bin/env python3
"""Load the generated seed dataset into a Dataverse environment through the Web API.

Usage:
    python load_seed.py --url https://mspdesk123456.crm4.dynamics.com --data data [--reset] [--workers 8]

Authentication: the access token in the MSPLAB_DATAVERSE_TOKEN environment variable when it
is set (Provision-ServiceDesk.ps1 passes the team user's token this way), otherwise a token
from the Azure CLI session of the signed-in user (az account get-access-token --resource <url>).

Every record is upserted with PATCH on its alternate key, so a re-run updates rather than
duplicates. --reset first deletes every Service Desk record (notes, tickets, articles,
seeded contacts and accounts, technicians, SLA policies, calendars); use it to re-anchor the
data before an event. The loader finishes by counting records per table and exits with
status 1 if any count differs from manifest.json.

Only the Python standard library is used.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

# (data file, entity set, alternate key column, filter that selects seeded rows for reset/count)
LOAD_ORDER = [
    ("businesscalendars", "msp_businesscalendars", "msp_calendarcode", "msp_calendarcode ne null"),
    ("slapolicies", "msp_slapolicies", "msp_policycode", "msp_policycode ne null"),
    ("technicians", "msp_technicians", "msp_techniciancode", "msp_techniciancode ne null"),
    ("accounts", "accounts", "msp_customercode", "msp_customercode ne null"),
    ("contacts", "contacts", "msp_contactcode", "msp_contactcode ne null"),
    ("account_patches", "accounts", "msp_customercode", None),
    ("knowledgearticles", "msp_knowledgearticles", "msp_articlenumber", "msp_articlenumber ne null"),
    ("tickets", "msp_tickets", "msp_ticketnumber", "msp_ticketnumber ne null"),
    ("ticketnotes", "msp_ticketnotes", "msp_notecode", "msp_notecode ne null"),
]
PRIMARY_KEYS = {"msp_businesscalendars": "msp_businesscalendarid", "msp_slapolicies": "msp_slapolicyid",
                "msp_technicians": "msp_technicianid", "accounts": "accountid", "contacts": "contactid",
                "msp_knowledgearticles": "msp_knowledgearticleid", "msp_tickets": "msp_ticketid",
                "msp_ticketnotes": "msp_ticketnoteid"}


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

    def request(self, method: str, path: str, body: dict | None = None, extra: dict | None = None) -> tuple[int, dict]:
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
                    return resp.status, (json.loads(raw) if raw else {})
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
                return err.code, payload
            except (urllib.error.URLError, TimeoutError):
                time.sleep(3 * attempt)
        return 599, {"error": {"message": "retries exhausted"}}


def key_path(entity_set: str, key_col: str, value: str) -> str:
    return f"{entity_set}({key_col}='{value.replace(chr(39), chr(39) * 2)}')"


def to_body(record: dict) -> dict:
    body = {k: v for k, v in record.items() if not k.startswith("_")}
    for nav, (entity_set, key_col, value) in record.get("_lookups", {}).items():
        body[f"{nav}@odata.bind"] = "/" + key_path(entity_set, key_col, value)
    return body


def upsert_all(dv: Dataverse, records: list[dict], entity_set: str, key_col: str, workers: int) -> list[str]:
    errors: list[str] = []

    def one(record: dict) -> None:
        key_value = record["_key"][key_col]
        status, payload = dv.request("PATCH", key_path(entity_set, key_col, key_value), to_body(record))
        if status >= 400:
            errors.append(f"{entity_set} {key_value}: HTTP {status} {payload.get('error', {}).get('message', '')[:300]}")

    with ThreadPoolExecutor(max_workers=workers) as pool:
        list(pool.map(one, records))
    return errors


def ids_matching(dv: Dataverse, entity_set: str, filt: str) -> list[str]:
    pk = PRIMARY_KEYS[entity_set]
    path = f"{entity_set}?$select={pk}&$filter={urllib.parse.quote(filt)}"
    ids: list[str] = []
    while path:
        status, payload = dv.request("GET", path, extra={"Prefer": "odata.maxpagesize=5000"})
        if status >= 400:
            raise SystemExit(f"Query failed on {entity_set}: {payload}")
        ids += [row[pk] for row in payload.get("value", [])]
        nxt = payload.get("@odata.nextLink")
        path = nxt.replace(dv.api, "") if nxt else ""
    return ids


def reset(dv: Dataverse, workers: int) -> None:
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
    parser.add_argument("--workers", type=int, default=8)
    args = parser.parse_args()

    dv = Dataverse(args.url)
    data = Path(args.data)
    manifest = json.loads((data / "manifest.json").read_text(encoding="utf-8"))
    print(f"Seed anchor (SLA Calculated On): {manifest['anchor']}")
    if args.reset:
        print("Removing existing Service Desk records")
        reset(dv, args.workers)

    all_errors: list[str] = []
    for name, entity_set, key_col, _ in LOAD_ORDER:
        records = json.loads((data / f"{name}.json").read_text(encoding="utf-8"))
        started = time.time()
        errors = upsert_all(dv, records, entity_set, key_col, args.workers)
        all_errors += errors
        print(f"  {name:18s} {len(records):5d} records in {time.time() - started:5.1f} s, {len(errors)} errors")

    print("Verifying counts")
    mismatches = []
    # Notes the agent writes during the lab use codes like TCK-10507-A1; seeded notes end -N<n>.
    # Count only seeded notes, so re-running the loader during or after the lab still verifies.
    count_filters = {"ticketnotes": "contains(msp_notecode,'-N')"}
    for name, entity_set, _, filt in LOAD_ORDER:
        if not filt:
            continue
        filt = count_filters.get(name, filt)
        expected = manifest["counts"][name]
        actual = len(ids_matching(dv, entity_set, filt))
        flag = "ok" if actual == expected else "MISMATCH"
        print(f"  {entity_set:22s} expected {expected:5d} actual {actual:5d} {flag}")
        if actual != expected:
            mismatches.append(entity_set)

    summary = {"anchor": manifest["anchor"], "errors": all_errors[:50], "error_count": len(all_errors),
               "mismatches": mismatches, "loaded_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    (data / "load-summary.json").write_text(json.dumps(summary, indent=1), encoding="utf-8")
    for line in all_errors[:20]:
        print("  error:", line)
    return 1 if (all_errors or mismatches) else 0


if __name__ == "__main__":
    raise SystemExit(main())
