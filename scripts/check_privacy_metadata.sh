#!/usr/bin/env bash

set -euo pipefail

readonly APP_INFO="CalorieBeta/Info.plist"
readonly APP_PRIVACY="CalorieBeta/PrivacyInfo.xcprivacy"
readonly CORE_PRIVACY="MyFitPlateCore/Sources/MyFitPlateCore/PrivacyInfo.xcprivacy"
readonly WATCH_INFO="MyFitPlateWatch Watch App/Info.plist"
readonly WATCH_PRIVACY="MyFitPlateWatch Watch App/PrivacyInfo.xcprivacy"

fail() {
    printf 'Privacy metadata check failed: %s\n' "$1" >&2
    exit 1
}

require_nonempty() {
    local file="$1"
    local key="$2"
    local value

    value="$(/usr/bin/plutil -extract "$key" raw -o - "$file" 2>/dev/null)" ||
        fail "$file is missing $key"
    [[ -n "${value//[[:space:]]/}" ]] || fail "$file has an empty $key"
}

require_value() {
    local file="$1"
    local key="$2"
    local expected="$3"
    local value

    value="$(/usr/bin/plutil -extract "$key" raw -o - "$file" 2>/dev/null)" ||
        fail "$file is missing $key"
    [[ "$value" == "$expected" ]] ||
        fail "$file has $key=$value; expected $expected"
}

require_project_overrides_match() {
    local file="$1"
    local key="$2"
    local expected_count="$3"
    local expected
    local setting
    local actual_count

    expected="$(/usr/bin/plutil -extract "$key" raw -o - "$file" 2>/dev/null)" ||
        fail "$file is missing $key"
    setting="INFOPLIST_KEY_${key} = \"${expected}\";"
    actual_count="$(/usr/bin/grep -F -c "$setting" MyFitPlate.xcodeproj/project.pbxproj || true)"
    [[ "$actual_count" == "$expected_count" ]] ||
        fail "project overrides for $key do not match $file in both configurations"
}

metadata_files=(
    "$APP_INFO"
    "$APP_PRIVACY"
    "$CORE_PRIVACY"
    "$WATCH_INFO"
    "$WATCH_PRIVACY"
    "CalorieBeta/CalorieBeta.entitlements"
    "CalorieWidget/Info.plist"
    "CalorieWidgetExtension.entitlements"
    "LiveActivity/Info.plist"
)

for file in "${metadata_files[@]}"; do
    [[ -f "$file" ]] || fail "$file does not exist"
    /usr/bin/plutil -lint "$file" >/dev/null || fail "$file is malformed"
done

app_usage_keys=(
    NSCameraUsageDescription
    NSPhotoLibraryUsageDescription
    NSHealthShareUsageDescription
    NSHealthUpdateUsageDescription
    NSLocationWhenInUseUsageDescription
    NSMicrophoneUsageDescription
    NSSpeechRecognitionUsageDescription
)

for key in "${app_usage_keys[@]}"; do
    require_nonempty "$APP_INFO" "$key"
done

require_nonempty "$WATCH_INFO" NSHealthShareUsageDescription
require_nonempty "$WATCH_INFO" NSHealthUpdateUsageDescription
require_project_overrides_match "$APP_INFO" NSCameraUsageDescription 2
require_project_overrides_match "$APP_INFO" NSPhotoLibraryUsageDescription 2
require_project_overrides_match "$APP_INFO" NSHealthShareUsageDescription 2
require_project_overrides_match "$APP_INFO" NSHealthUpdateUsageDescription 2
require_project_overrides_match "$WATCH_INFO" NSHealthShareUsageDescription 2
require_project_overrides_match "$WATCH_INFO" NSHealthUpdateUsageDescription 2
require_value "$WATCH_INFO" WKCompanionAppBundleIdentifier MyFitPlate.CalorieBeta
require_value "$APP_INFO" ITSAppUsesNonExemptEncryption false
require_value "$APP_INFO" USDA_API_KEY '$(USDA_API_KEY)'
require_value "$APP_PRIVACY" NSPrivacyTracking false
require_value "$WATCH_PRIVACY" NSPrivacyTracking false

printf 'Privacy metadata source check passed.\n'
