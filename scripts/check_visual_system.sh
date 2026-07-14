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

if (( status != 0 )); then
  printf 'Use AppSurfaceModifier, AppActionButtonStyle, and semantic flat colors instead.\n' >&2
  exit "$status"
fi

printf 'Visual-system source check passed.\n'
