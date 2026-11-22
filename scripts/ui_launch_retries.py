"""List cases eligible for one fresh-simulator retry after XCTest could not launch the app."""

import argparse
import json
import re
from pathlib import Path


LAUNCH_FAILURE = re.compile(
    r"Failed to get background assertion for target app with pid \d+: Timed out while acquiring background assertion\.?"
)


def classify_failures(summary):
    if summary.get("result") != "Failed" or not summary.get("testFailures"):
        return [], ["Missing XCTest failure details"]

    launch = set()
    assertions = set()
    incomplete = False
    for failure in summary["testFailures"]:
        identifier = failure.get("testIdentifierString", "")
        if not re.fullmatch(r"\w+/test\w+\(\)", identifier):
            incomplete = True
        elif LAUNCH_FAILURE.fullmatch(failure.get("failureText", "").strip()):
            launch.add(identifier)
        else:
            assertions.add(identifier)

    blocking = sorted(assertions)
    if incomplete or len(launch | assertions) != summary.get("failedTests"):
        blocking.append("Incomplete XCTest failure inventory")
    return sorted(launch - assertions), blocking


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("summary", type=Path)
    parser.add_argument("--blocking-report", type=Path, required=True)
    args = parser.parse_args()
    retry, blocking = classify_failures(json.loads(args.summary.read_text()))
    args.blocking_report.write_text("".join(f"{entry}\n" for entry in blocking))
    for identifier in retry:
        print(identifier)
