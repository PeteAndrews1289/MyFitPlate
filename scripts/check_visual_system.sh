#!/bin/bash

set -euo pipefail

# These symbols belong to the retired soft-glass generation. Keep the check narrow so intentional
# data-chart, shimmer, and exported-poster gradients remain available.
readonly forbidden_patterns=(
  '\.asCard[[:space:]]*\('
  '\.glassCard[[:space:]]*\('
  'GlassCardModifier'
  'PrimaryButtonStyle[[:space:]]*\('
  'SecondaryButtonStyle[[:space:]]*\('
  'LinearGradient\.brandGradient'
  'static[[:space:]]+var[[:space:]]+brandGradient'
)

status=0

for pattern in "${forbidden_patterns[@]}"; do
  if matches=$(git grep -n -E "$pattern" -- '*.swift'); then
    printf 'Retired visual-system symbol found:\n%s\n' "$matches" >&2
    status=1
  fi
done

# Material is reserved for transient chrome and overlays. Each allowlisted file currently owns one
# such layer; a second use in the same file still fails so the exception cannot become a blanket.
readonly material_pattern='\.(ultraThinMaterial|thinMaterial|regularMaterial|thickMaterial)'
readonly material_allowlist=(
  'CalorieBeta/UIComponents/CustomTabBar.swift'
  'CalorieBeta/UIComponents/ImageProcessingView.swift'
  'CalorieBeta/Features/Maia/AIChatComponents.swift'
  'CalorieBeta/Features/Workouts/RunningViews.swift'
  'CalorieWidget/CalorieWidget.swift'
)

material_matches="$(git grep -n -E "$material_pattern" -- '*.swift' || true)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  is_allowed=0
  for allowed_file in "${material_allowlist[@]}"; do
    if [[ "$file" == "$allowed_file" ]]; then
      is_allowed=1
      break
    fi
  done
  if (( is_allowed == 0 )); then
    printf 'Material outside the transient-shell allowlist:\n%s\n' "$match" >&2
    status=1
  fi
done <<< "$material_matches"

for allowed_file in "${material_allowlist[@]}"; do
  count=$(printf '%s\n' "$material_matches" | awk -F: -v file="$allowed_file" '$1 == file { count += 1 } END { print count + 0 }')
  if (( count > 1 )); then
    printf 'More than one material layer found in allowlisted file %s (%d).\n' "$allowed_file" "$count" >&2
    status=1
  fi
done

# Gradients remain valid for data charts, loading states, and exported run artwork, but not for
# controls or ordinary app surfaces.
readonly gradient_allowlist=(
  'CalorieBeta/Features/Home/WeeklyCheckInView.swift'
  'CalorieBeta/Features/Workouts/ExerciseTrendChartView.swift'
  'CalorieBeta/Features/Workouts/RunStoryPosterView.swift'
  'CalorieBeta/UIComponents/ShimmerModifier.swift'
  'MyFitPlateCore/Sources/MyFitPlateCore/DesignSystem.swift'
)

gradient_matches="$(git grep -n -E 'LinearGradient[[:space:]]*\(' -- '*.swift' || true)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  is_allowed=0
  for allowed_file in "${gradient_allowlist[@]}"; do
    if [[ "$file" == "$allowed_file" ]]; then
      is_allowed=1
      break
    fi
  done
  if (( is_allowed == 0 )); then
    printf 'Gradient outside the chart/loading/export allowlist:\n%s\n' "$match" >&2
    status=1
  fi
done <<< "$gradient_matches"

for allowed_file in "${gradient_allowlist[@]}"; do
  count=$(printf '%s\n' "$gradient_matches" | awk -F: -v file="$allowed_file" '$1 == file { count += 1 } END { print count + 0 }')
  if (( count > 1 )); then
    printf 'More than one gradient found in allowlisted file %s (%d).\n' "$allowed_file" "$count" >&2
    status=1
  fi
done

# Shadows are limited to persistent app chrome, transient guidance, and exported artwork. Content
# surfaces should establish hierarchy through spacing, borders, and semantic color instead.
readonly shadow_allowlist=(
  'CalorieBeta/Features/Maia/AIChatComponents.swift'
  'CalorieBeta/Features/Workouts/ExerciseNoteView.swift'
  'CalorieBeta/Features/Workouts/RunStoryPosterView.swift'
  'CalorieBeta/UIComponents/CustomTabBar.swift'
  'CalorieBeta/UIComponents/SpotlightTextView.swift'
  'CalorieBeta/UIComponents/SpotlightTourOverlay.swift'
  'MyFitPlateCore/Sources/MyFitPlateCore/SpotlightModifier.swift'
  'MyFitPlateCore/Sources/MyFitPlateCore/ToastManager.swift'
)

shadow_matches="$(git grep -n -E '\.shadow[[:space:]]*\(' -- '*.swift' || true)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  is_allowed=0
  for allowed_file in "${shadow_allowlist[@]}"; do
    if [[ "$file" == "$allowed_file" ]]; then
      is_allowed=1
      break
    fi
  done
  if (( is_allowed == 0 )); then
    printf 'Shadow outside the shell/overlay/export allowlist:\n%s\n' "$match" >&2
    status=1
  fi
done <<< "$shadow_matches"

for allowed_file in "${shadow_allowlist[@]}"; do
  count=$(printf '%s\n' "$shadow_matches" | awk -F: -v file="$allowed_file" '$1 == file { count += 1 } END { print count + 0 }')
  if (( count > 1 )); then
    printf 'More than one shadow found in allowlisted file %s (%d).\n' "$allowed_file" "$count" >&2
    status=1
  fi
done

# Release-reachable UI uses the shared signal and domain vocabulary. Direct spectrum colors are
# valid only where the color itself is measured/categorical data, a physical plate standard,
# celebration/export artwork, inside the deliberately inaccessible social prototype, or where the
# palette itself defines the semantic critical color. Scan app roots and extensions, not only the
# feature folder, so top-level screens, widgets, and Live Activities cannot bypass this guard.
readonly direct_color_pattern='\.(red|orange|yellow|blue|cyan|indigo|purple|pink|green|teal)([^[:alnum:]_]|$)'
readonly direct_color_allowlist=(
  'CalorieBeta/Features/Home/WeeklyCheckInView.swift'
  'CalorieBeta/Features/Home/WeeklyRecapView.swift'
  'CalorieBeta/Features/Nutrition/CelebrationOverlayView.swift'
  'CalorieBeta/Features/Nutrition/PlateCalculatorView.swift'
  'CalorieBeta/Features/Workouts/RunningViews.swift'
  'CalorieBeta/Features/Workouts/RunStoryPosterView.swift'
  'CalorieBeta/Features/Wellness/CycleTrackingView.swift'
  'CalorieBeta/Features/Wellness/SleepReportCard.swift'
  'CalorieBeta/Features/Wellness/WellnessScoreDetailView.swift'
  'CalorieBeta/Features/Community/CommunityHubView.swift'
  'CalorieBeta/Features/Community/CreateGroupView.swift'
  'CalorieBeta/Features/Community/CreatePostView.swift'
  'CalorieBeta/Features/Community/GroupSelectionView.swift'
  'CalorieBeta/Features/Community/JoinGroupConfirmationView.swift'
  'MyFitPlateCore/Sources/MyFitPlateCore/AppVisualSystem.swift'
)

direct_color_matches="$(git grep -n -E "$direct_color_pattern" -- \
  'CalorieBeta' \
  'CalorieWidget' \
  'LiveActivity' \
  'MyFitPlateCore/Sources/MyFitPlateCore' || true)"
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  is_allowed=0
  for allowed_file in "${direct_color_allowlist[@]}"; do
    if [[ "$file" == "$allowed_file" ]]; then
      is_allowed=1
      break
    fi
  done
  if (( is_allowed == 0 )); then
    printf 'Direct spectrum color outside the data/art/prototype allowlist:\n%s\n' "$match" >&2
    status=1
  fi
done <<< "$direct_color_matches"

# BrandPrimary is deliberately vivid for fills, charts, and exported artwork. It is too light to
# carry small text and symbols on ordinary app surfaces, so foreground content uses the adaptive
# BrandForeground/AppPalette.brandText role. Keep a tightly counted exception for measured charts
# and the dark run-story export where the vivid brand color is itself part of the artwork.
readonly brand_foreground_pattern='foreground(Style|Color).*(brandPrimary|AppPalette\.brand([^[:alnum:]_]|$))'
readonly brand_foreground_allowlist=(
  'CalorieBeta/Features/Wellness/WeightChartView.swift:3'
  'CalorieBeta/Features/Workouts/ExerciseTrendChartView.swift:2'
  'CalorieBeta/Features/Workouts/WorkoutCompleteAnalyticsView.swift:1'
  'CalorieBeta/Features/Workouts/RunningViews.swift:1'
  'CalorieBeta/Features/Workouts/RunStoryPosterView.swift:2'
)

brand_foreground_matches="$(git grep -n -E "$brand_foreground_pattern" -- \
  'CalorieBeta' \
  'CalorieWidget' \
  'LiveActivity' \
  'MyFitPlateWatch Watch App' \
  'MyFitPlateCore/Sources/MyFitPlateCore' || true)"

while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  file="${match%%:*}"
  is_allowed=0
  for exception in "${brand_foreground_allowlist[@]}"; do
    allowed_file="${exception%:*}"
    if [[ "$file" == "$allowed_file" ]]; then
      is_allowed=1
      break
    fi
  done
  if (( is_allowed == 0 )); then
    printf 'Low-contrast brand color used as foreground:\n%s\n' "$match" >&2
    status=1
  fi
done <<< "$brand_foreground_matches"

for exception in "${brand_foreground_allowlist[@]}"; do
  allowed_file="${exception%:*}"
  allowed_count="${exception##*:}"
  count=$(printf '%s\n' "$brand_foreground_matches" | awk -F: -v file="$allowed_file" '$1 == file { count += 1 } END { print count + 0 }')
  if (( count > allowed_count )); then
    printf 'Too many vivid-brand foregrounds in allowlisted file %s (%d > %d).\n' \
      "$allowed_file" "$count" "$allowed_count" >&2
    status=1
  fi
done

# Selected controls, completed timeline nodes, and confirmed actions use bright semantic fills.
# Their labels and symbols need the dark on-brand/on-signal role; white falls below contrast
# targets on the current green, blue, aqua, amber, and violet palette.
readonly conditional_white_pattern='(isSelected|didLog|didConfirm|event\.state|day\.hasTraining).*white'
if matches=$(git grep -n -E "$conditional_white_pattern" -- \
  'CalorieBeta' \
  'CalorieWidget' \
  'MyFitPlateWatch Watch App' \
  'MyFitPlateCore/Sources/MyFitPlateCore'); then
  printf 'White foreground used conditionally on a bright brand or signal fill:\n%s\n' "$matches" >&2
  status=1
fi

if (( status != 0 )); then
  printf 'Use shared surfaces, actions, and AppPalette/AppSignalRole semantic colors instead.\n' >&2
  exit "$status"
fi

printf 'Visual-system source check passed.\n'
