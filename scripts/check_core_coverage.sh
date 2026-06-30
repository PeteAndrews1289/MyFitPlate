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
FLOOR="${CORE_COVERAGE_MINIMUM:-70.0}"

# Search the SPM build dir (what CI's `swift test` writes) and the agents' local
# Xcode derived-data path — whichever exist. Pass only existing dirs and use
# `-print -quit`: `find` over a missing dir, or `... | head -1` closing the pipe
# early, exits non-zero, which under `set -euo pipefail` aborts the whole script.
# (That is exactly what broke CI — `.codex_xcode` does not exist on the runner.)
SEARCH_DIRS=()
[[ -d "$PKG/.build" ]] && SEARCH_DIRS+=("$PKG/.build")
[[ -d ".codex_xcode" ]] && SEARCH_DIRS+=(".codex_xcode")

PROF=""
BIN=""
if (( ${#SEARCH_DIRS[@]} > 0 )); then
  PROF="$(find "${SEARCH_DIRS[@]}" -name 'default.profdata' -print -quit 2>/dev/null || true)"
  BIN="$(find "${SEARCH_DIRS[@]}" -type f -name "${PKG}PackageTests" -print -quit 2>/dev/null || true)"
fi

if [[ -z "$PROF" || -z "$BIN" ]]; then
  echo "::error::Coverage data missing. Run 'swift test --enable-code-coverage --package-path $PKG' first."
  exit 1
fi

# Total line-coverage % over Core source only (exclude the test bundle and .build dependencies).
PERCENT="$(xcrun llvm-cov report "$BIN" -instr-profile="$PROF" \
  -ignore-filename-regex='(\.build|\.codex_xcode|/Tests/|/Mocks/|/Previews/|HealthKitManager\.swift|HealthKitViewModel\.swift|NotificationManager\.swift)' 2>/dev/null \
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
