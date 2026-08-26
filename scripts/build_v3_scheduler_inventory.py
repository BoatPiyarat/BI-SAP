#!/usr/bin/env python3
"""Build exhaustive, paginated Cloud Scheduler non-overlap evidence as JSON."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import subprocess
import urllib.parse
import urllib.request
from zoneinfo import ZoneInfo

GENERATOR = "scripts/build_v3_scheduler_inventory.py:v1"
API_ROOT = "https://cloudscheduler.googleapis.com/v1"
MONTHS = {name: i for i, name in enumerate(
          ("JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"), 1)}
DAYS = {name: i for i, name in enumerate(("MON", "TUE", "WED", "THU", "FRI", "SAT"), 1)}
DAYS["SUN"] = 0


def parse_duration(value: str) -> int:
    if not value or not value.endswith("s"):
        return 0
    return max(0, int(float(value[:-1])))


def expand_atom(atom: str, low: int, high: int, names: dict[str, int]) -> set[int]:
    step = 1
    if "/" in atom:
        atom, raw_step = atom.split("/", 1)
        step = int(raw_step)
        if step < 1:
            raise ValueError("cron step must be positive")
    def number(raw: str) -> int:
        return names.get(raw.upper(), int(raw) if raw.lstrip("-").isdigit() else -999)
    if atom == "*":
        start, end = low, high
    elif "-" in atom:
        left, right = atom.split("-", 1)
        start, end = number(left), number(right)
    else:
        value = number(atom)
        start, end = value, value
    if start < low or end > high or start > end:
        raise ValueError(f"cron value {atom!r} outside {low}..{high}")
    return set(range(start, end + 1, step))


def field(raw: str, low: int, high: int, names: dict[str, int] | None = None) -> set[int]:
    values: set[int] = set()
    for atom in raw.split(","):
        values |= expand_atom(atom, low, high, names or {})
    return values


def cron_matches(expression: str, local: dt.datetime) -> bool:
    parts = expression.split()
    if len(parts) != 5:
        raise ValueError(f"expected five cron fields: {expression!r}")
    minutes = field(parts[0], 0, 59)
    hours = field(parts[1], 0, 23)
    dom = field(parts[2], 1, 31)
    months = field(parts[3], 1, 12, MONTHS)
    dow = {0 if value == 7 else value for value in field(parts[4], 0, 7,
                                                           {**DAYS, "SUN": 0})}
    cron_dow = (local.weekday() + 1) % 7
    dom_match, dow_match = local.day in dom, cron_dow in dow
    day_match = (dom_match and dow_match) if parts[2] == "*" or parts[4] == "*" else (dom_match or dow_match)
    return local.minute in minutes and local.hour in hours and local.month in months and day_match


def access_token() -> str:
    command = ([os.environ.get("COMSPEC", "cmd.exe"), "/d", "/s", "/c",
                "gcloud auth print-access-token"] if os.name == "nt"
               else ["gcloud", "auth", "print-access-token"])
    result = subprocess.run(command, check=True,
                            capture_output=True, text=True)
    return result.stdout.strip()


def list_jobs(project: str, region: str) -> tuple[list[dict], int, str]:
    token, page_token, pages, jobs = access_token(), "", 0, []
    raw_pages: list[bytes] = []
    while True:
        query = urllib.parse.urlencode({"pageSize": 500, "pageToken": page_token})
        url = f"{API_ROOT}/projects/{project}/locations/{region}/jobs?{query}"
        request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
        raw_pages.append(raw)
        payload = json.loads(raw)
        pages += 1
        jobs.extend(payload.get("jobs", []))
        page_token = payload.get("nextPageToken", "")
        if not page_token:
            break
    digest = hashlib.sha256(b"\n".join(raw_pages)).hexdigest()
    return jobs, pages, digest


def iso(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default="pacific-plating-282708")
    parser.add_argument("--region", default="asia-southeast1")
    parser.add_argument("--horizon-days", type=int, default=8)
    parser.add_argument("--minimum-window-seconds", type=int, default=1800)
    args = parser.parse_args()
    if args.horizon_days < 7 or args.minimum_window_seconds < 1:
        parser.error("horizon must be >=7 days and minimum window must be positive")

    checked = dt.datetime.now(dt.timezone.utc)
    start = checked.replace(second=0, microsecond=0)
    end = start + dt.timedelta(days=args.horizon_days)
    minute_count = int((end - start).total_seconds() // 60)
    jobs, pages, raw_hash = list_jobs(args.project, args.region)
    rendered = []
    for job in sorted(jobs, key=lambda item: item.get("name", "")):
        item = dict(job)
        windows = []
        if item.get("state") == "ENABLED":
            zone = ZoneInfo(item.get("timeZone") or "UTC")
            duration = max(args.minimum_window_seconds, parse_duration(item.get("attemptDeadline", "")))
            cursor = start
            while cursor < end:
                if cron_matches(item["schedule"], cursor.astimezone(zone)):
                    windows.append({"start": iso(cursor), "end": iso(cursor + dt.timedelta(seconds=duration))})
                cursor += dt.timedelta(minutes=1)
            item.update(cronExpansionVersion="V1_EXHAUSTIVE_MINUTE",
                        evaluatedMinuteCount=minute_count, windowCount=len(windows), windows=windows)
        rendered.append(item)
    evidence = {
        "generator": GENERATOR, "sourceApi": "cloudscheduler.googleapis.com/v1",
        "project": args.project, "region": args.region, "checkedAt": iso(checked),
        "horizonStart": iso(start), "horizonEnd": iso(end), "horizonMinuteCount": minute_count,
        "jobCount": len(rendered), "enabledJobCount": sum(j.get("state") == "ENABLED" for j in rendered),
        "pagesFetched": pages, "paginationComplete": True, "rawInventorySha256": raw_hash, "jobs": rendered,
    }
    print(json.dumps(evidence, separators=(",", ":"), sort_keys=True))


if __name__ == "__main__":
    main()
