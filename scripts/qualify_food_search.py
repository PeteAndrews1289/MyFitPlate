#!/usr/bin/env python3
"""Opt-in, bounded catalog reads. Never reads account tokens or user food logs.

USDA credentials come from USDA_API_KEY or the local ignored secrets.xcconfig;
the app's JSON search and api_key credential transport are reproduced. Raw public responses
are compressed beside append-only request metadata for replay through Swift.
This measures the named host/provider transport, not app UI or device latency.
"""
import argparse
import datetime
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
OFF_FIELDS = "code,product_name,brands,serving_size,serving_quantity,last_modified_t,nutriments"


def configured_usda_key():
    value = os.environ.get("USDA_API_KEY", "").strip()
    if not value:
        config = ROOT / "secrets.xcconfig"
        if config.exists():
            match = re.search(r"^\s*USDA_API_KEY\s*=\s*(.*?)\s*$", config.read_text(), re.M)
            value = match.group(1).strip().strip('"') if match else ""
    if not value or "$(" in value or value == "DEMO_KEY":
        raise SystemExit("A dedicated USDA key is required; no key was printed or requested from an account.")
    return value


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--live", action="store_true", help="Required to make public catalog requests")
    p.add_argument("--provider", choices=["usda", "off"], required=True)
    p.add_argument("--corpus", type=Path, default=ROOT / "docs/wave-4-assets/search-qualification/corpus.json")
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--max-queries", type=int, default=12)
    p.add_argument("--variants", nargs="+", default=["all_words"], choices=["broad", "all_words", "full", "fields"])
    p.add_argument("--ids", nargs="*", help="Optional explicit corpus IDs; max-queries still applies")
    p.add_argument("--delay", type=float, default=0.35)
    args = p.parse_args()
    if not args.live:
        raise SystemExit("No network requests made. Use --live for the explicit catalog benchmark.")
    if not 1 <= args.max_queries <= 200:
        raise SystemExit("max-queries must be between1 and200")
    valid = {"usda": {"broad", "all_words"}, "off": {"full", "fields"}}[args.provider]
    if not set(args.variants) <= valid or len(set(args.variants)) != len(args.variants):
        raise SystemExit("Invalid or duplicate provider variants")
    corpus = json.loads(args.corpus.read_text())
    queries = [q for q in corpus["queries"] if not args.ids or q["id"] in args.ids][:args.max_queries]
    if not queries or any(not re.fullmatch(r"q\d{3}", q["id"]) or not 2 <= len(q["query"]) <= 160 for q in queries):
        raise SystemExit("Expected bounded public-food query records")
    key = configured_usda_key() if args.provider == "usda" else None
    args.output.mkdir(parents=True, exist_ok=True)
    args.output.chmod(0o700)
    (args.output / "responses").mkdir(exist_ok=True)
    index = args.output / "requests.jsonl"
    previous = [json.loads(s) for s in index.read_text().splitlines()] if index.exists() else []
    done = {(r["query_id"], r["provider"], r["variant"]) for r in previous}
    # OFF's published search limit is10/min/IP; use one request every6.5seconds.
    interval = max(args.delay, 6.5 if args.provider == "off" else 0.1)
    last_started = 0.0
    completed = 0
    for item in queries:
        for variant in args.variants:
            if (item["id"], args.provider, variant) in done:
                continue  # failures stay recorded; resume does not hide/retry them
            time.sleep(max(0, interval - (time.monotonic() - last_started)))
            headers = {"Accept": "application/json", "User-Agent": "MyFitPlate/2.4 (search QA; https://github.com/PeteAndrews1289/MyFitPlate)"}
            payload = None
            if args.provider == "usda":
                params = {"api_key": key}
                criteria = {"query": item["query"], "pageSize": 20, "requireAllWords": variant == "all_words",
                            "dataType": ["Branded", "Foundation", "SR Legacy", "Survey (FNDDS)"]}
                payload = json.dumps(criteria).encode()
                headers["Content-Type"] = "application/json"
                endpoint = "https://api.nal.usda.gov/fdc/v1/foods/search"
            else:
                params = {"search_terms": item["query"], "search_simple": "1", "action": "process", "json": "1", "page_size": "25"}
                if variant == "fields": params["fields"] = OFF_FIELDS
                endpoint = "https://world.openfoodfacts.org/cgi/search.pl"
            record = {"query_id": item["id"], "provider": args.provider, "variant": variant,
                      "query": item["query"], "category": item["category"], "method": "POST" if payload else "GET",
                      "started_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                      "transport_scope": "host urllib; public catalog; no app auth, merge, rendering or device timing",
                      "timeout_seconds": 6, "credential_transport": "api_key query; URL never recorded" if key else "none"}
            started = last_started = time.monotonic()
            remaining = None
            try:
                request = urllib.request.Request(endpoint + "?" + urllib.parse.urlencode(params), data=payload, headers=headers)
                with urllib.request.urlopen(request, timeout=6) as response:
                    body = response.read()
                    record["http_status"] = response.status
                    remaining = response.headers.get("X-RateLimit-Remaining")
                record["elapsed_ms"] = round((time.monotonic() - started) * 1000, 3)
                if key and key.encode() in body:
                    body = body.replace(key.encode(), b"[REDACTED]")
                    record["credential_redacted_from_response"] = True
                parsed = json.loads(body)
                record["bytes"] = len(body)
                record["sha256"] = hashlib.sha256(body).hexdigest()
                record["result_count"] = len(parsed.get("foods" if args.provider == "usda" else "products", []))
                record["total_hits"] = parsed.get("totalHits" if args.provider == "usda" else "count")
                destination = Path("responses") / f"{item['id']}-{args.provider}-{variant}.json.gz"
                with gzip.open(args.output / destination, "wb") as out: out.write(body)
                record["capture"] = str(destination)
            except Exception as error:
                # Exception strings may contain URLs. Store only type/status, never details.
                record.update(elapsed_ms=round((time.monotonic()-started)*1000,3),
                              error_type=type(error).__name__, http_status=getattr(error,"code",None))
            with index.open("a") as out:
                out.write(json.dumps(record, sort_keys=True) + "\n")
            completed += 1
            if completed % 20 == 0 or "error_type" in record:
                print(json.dumps({"completed_this_run":completed,"query_id":item["id"],"provider":args.provider,"variant":variant,"status":record.get("http_status"),"error":record.get("error_type")}),flush=True)
            if record.get("http_status") in [401,403,429] or (remaining and remaining.isdigit() and int(remaining) <= 20):
                print("Stopped at authentication/rate-limit boundary; recorded failures remain visible.",flush=True)
                return
    print(json.dumps({"completed_this_run":completed,"records":len(previous)+completed,"provider":args.provider,"network":"completed"}),flush=True)


if __name__ == "__main__": main()
