# Milestone Plan

Milestones merge in sequence. Each milestone ends with a green required GitHub Actions run on `main`, its acceptance evidence linked in the pull request or release notes, and no open severity-1 defect in its scope.

| Milestone | Outcome | Spec |
|---|---|---|
| 0 | Repository, CI contract, app skeleton | [M0](M0-foundation.md) |
| 1 | Provider and credential feasibility | [M1](M1-provider-spike.md) |
| 2 | Portable project runtime | [M2](M2-project-runtime.md) |
| 3 | Prompt-to-playable generation | [M3](M3-generation-loop.md) |
| 4 | Assets and visual review | [M4](M4-assets-and-vision.md) |
| 5 | Authoring experience and portability | [M5](M5-product-workflows.md) |
| 6 | Static sharing | [M6](M6-sharing.md) |
| 7 | Public-release hardening | [M7](M7-release.md) |
| Later | Declarative native runtime | [Future](future-native-runtime.md) |

## Common gate

Every milestone must add or update tests for its behavior. Required CI uses a pinned Xcode/macOS image and includes build, unit tests, static checks, secret scanning, and license checks. Runtime milestones add simulator integration and UI tests. A milestone is not complete when tests are skipped because credentials, hardware, or a host are unavailable; those tests must use fakes in required CI and run a documented opt-in live lane where needed.
