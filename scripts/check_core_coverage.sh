#!/usr/bin/env bash
#
# Enforces a minimum line-coverage floor for the MyFitPlateCore package *source*
# (where the app's real logic now lives after modularization).
#
# Run from the repo root AFTER:
#   swift test --enable-code-coverage --package-path MyFitPlateCore
#
# Override the floor with the CORE_COVERAGE_MINIMUM env var.
set -euo pipefail

PKG="MyFitPlateCore"
FLOOR="${CORE_COVERAGE_MINIMUM:-10.0}"

PROF="$(find "$PKG/.build" -name 'default.profdata' 2>/dev/null | head -1)"
BIN="$(find "$PKG/.build" -type f -name "${PKG}PackageTests" 2>/dev/null | head -1)"

if [[ -z "$PROF" || -z "$BIN" ]]; then
  echo "::error::Coverage data missing. Run 'swift test --enable-code-coverage --package-path $PKG' first."
  exit 1
fi

# Total line-coverage % over Core source only (exclude the test bundle and .build dependencies).
PERCENT="$(xcrun llvm-cov report "$BIN" -instr-profile="$PROF" \
  -ignore-filename-regex='(\.build|/Tests/)' 2>/dev/null \
  | awk '/^TOTAL/ { gsub("%","",$10); print $10 }')"

if [[ -z "$PERCENT" ]]; then
  echo "::error::Could not parse MyFitPlateCore coverage."
  exit 1
fi

printf 'MyFitPlateCore line coverage: %s%% (floor %s%%)\n' "$PERCENT" "$FLOOR"

BELOW="$(awk -v p="$PERCENT" -v f="$FLOOR" 'BEGIN { print (p+0 < f+0) ? "yes" : "no" }')"
if [[ "$BELOW" == "yes" ]]; then
  echo "::error::MyFitPlateCore coverage ${PERCENT}% is below the ${FLOOR}% floor."
  exit 1
fi

echo "Core coverage floor satisfied."
