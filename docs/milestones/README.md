# Milestone Plan

Milestones merge in sequence. Each one ends with its acceptance evidence and a green required GitHub Actions run on `main`. A later milestone cannot waive an earlier gate.

| Milestone | Outcome | Spec |
|---|---|---|
| 0 | Risk spike: ChatGPT auth, WebKit sandbox, Apple Guideline 4.7 | [M0](M0-risk-spike.md) |
| 1 | Vertical slice: prompt → Phaser → checks → play → edit → patch/reload | [M1](M1-vertical-slice.md) |
| 2 | Reliability: patch validation, two-layer checks, rollback, repair | [M2](M2-reliability.md) |
| 3 | Projects: persistence, revisions, Files import/export | [M3](M3-projects.md) |
| 4 | Assets: procedural/import baseline, later image experiments | [M4](M4-assets.md) |
| 5 | Providers: complete stable adapter set | [M5](M5-providers.md) |
| 6 | Sharing and App Store readiness | [M6](M6-sharing-app-store.md) |
| Later | Declarative native runtime | [Future](future-native-runtime.md) |

## Common gate

Every milestone adds or updates tests for its behavior. Required CI uses a pinned Xcode/macOS image and includes build, unit tests, static checks, secret scanning, license checks, and the case-insensitive prohibited-name check. Runtime milestones add simulator integration/UI tests. Hardware, credential, and host behavior use fakes in required CI plus documented opt-in live lanes where needed.
