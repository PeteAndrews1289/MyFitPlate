#!/usr/bin/env bash
# Enforce Core source line coverage from the current SwiftPM test run.
# Run after: swift test --enable-code-coverage --package-path MyFitPlateCore
set -euo pipefail
PKG="MyFitPlateCore"
FLOOR="${CORE_COVERAGE_MINIMUM:-80.0}"
# Ask SwiftPM for the active report. Scanning .build can pair a stale binary from
# another build system with this run's profile (notably with Xcode 27's SwiftPM).
COVERAGE_JSON="$(swift test --package-path "$PKG" --show-codecov-path)"
python3 - "$COVERAGE_JSON" "$FLOOR" <<'PYTHON'
import json
import re
import sys
from pathlib import Path

report = Path(sys.argv[1])
if not report.is_file():
    sys.exit("::error::Coverage data missing. Run swift test --enable-code-coverage --package-path MyFitPlateCore first.")
excluded = re.compile(r"(/checkouts/|\.build|\.codex_xcode|/Tests/|/Mocks/|/Previews/|HealthKitManager\.swift|HealthKitViewModel\.swift|NotificationManager\.swift)")
files = {
    item["filename"]: item["summary"]["lines"]
    for entry in json.loads(report.read_text())["data"]
    for item in entry["files"]
    if not excluded.search(item["filename"])
}
total = sum(item["count"] for item in files.values())
if not total:
    sys.exit("::error::No Core source lines were found in the coverage report.")
percent = 100 * sum(item["covered"] for item in files.values()) / total
floor = float(sys.argv[2])
print(f"MyFitPlateCore line coverage: {percent:.2f}% (floor {floor:.2f}%)")
if percent < floor:
    sys.exit(f"::error::Core coverage {percent:.2f}% is below {floor:.2f}%.")
print("Core coverage floor satisfied.")
PYTHON
