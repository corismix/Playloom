# Milestone 0: Foundation

## Outcome

A buildable iPhone/iPad SwiftUI skeleton with enforceable CI and module boundaries, without product features or provider calls.

## Deliverables

- Xcode project targeting a currently supported iOS baseline, agreed when implementation starts.
- Modules/targets for AppShell, ProjectStore, ProviderKit, GameRuntime, Evaluation, and test support.
- One placeholder project-library screen and settings route.
- Structured logging with privacy annotations and a redaction test harness.
- Formatting/lint configuration, dependency policy, GPL headers, contribution notes, and threat-model checklist.
- GitHub Actions on a pinned macOS image with build and unit-test jobs.
- Branch protection documentation requiring the CI workflow on `main`.

## Tests

- iPhone and iPad simulator build.
- Module dependency test or build rule prevents web runtime from importing credential internals.
- Log redaction canaries.
- Repository scan proves the prohibited legal name is absent, including case-insensitive variants.
- License and secret scans.

## Acceptance

- Fresh checkout builds without private configuration.
- No app code contains a real provider credential or endpoint secret.
- Required CI is green on `main`.
