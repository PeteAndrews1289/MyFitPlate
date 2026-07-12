## Summary

- 

## Verification

- [ ] Core tests pass and line coverage remains at or above 80%.
- [ ] App unit and UI smoke tests pass locally or in CI.
- [ ] Unsigned generic-device Release build passes.
- [ ] Strict SwiftLint and `git diff --check` pass.
- [ ] No new secrets or generated build logs are included.

## Release Safety

- [ ] Analytics and Crashlytics changes avoid account, food, workout, route, Health, prompt, and free-form values.
- [ ] New network or AI behavior has a visible failure/retry path.
- [ ] Risky server or community behavior is behind a default-off flag with a rollback path.
- [ ] User-facing copy, dark mode, Dynamic Type, and VoiceOver impact were reviewed for touched screens.
- [ ] `ROADMAP.md`, relevant docs, and `AGENT_HANDOFF.local.md` reflect meaningful product or architecture changes.

## Not In This PR

- List device, console, deployment, production-data, or App Store actions that still require the owner.
