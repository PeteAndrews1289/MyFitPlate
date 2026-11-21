"""List cases eligible for one fresh-simulator retry after XCTest could not launch the app."""

import json
import re
import sys
from pathlib import Path


def launch_failures(summary):
    failures = summary.get("testFailures", [])
    identifiers = set()
    for failure in failures:
        if not re.fullmatch(
            r"Failed to get background assertion for target app with pid \d+: Timed out while acquiring background assertion\.?",
            failure.get("failureText", "").strip(),
        ):
            return []
        identifier = failure.get("testIdentifierString", "")
        if not re.fullmatch(r"\w+/test\w+\(\)", identifier):
            return []
        identifiers.add(identifier)
    if summary.get("result") == "Failed" and len(identifiers) == summary.get("failedTests"):
        return sorted(identifiers)
    return []


if __name__ == "__main__":
    for identifier in launch_failures(json.loads(Path(sys.argv[1]).read_text())):
        print(identifier)
