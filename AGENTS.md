# Playloom agent guide

## Build and test

- This is an XcodeGen iOS project, not a SwiftPM package. `project.yml` is the source of truth; `Playloom.xcodeproj/` is generated and ignored. Change `project.yml`, then regenerate instead of editing the project file.
- CI installs XcodeGen with Homebrew; a fresh machine can use `brew install xcodegen`. Xcode resolves the exact Textual package version declared in `project.yml`; there is no separate dependency-install task.
- CI builds with Swift 6 strict concurrency for iOS 18+ on the macOS 26 runner. Generate the project before any Xcode build from a fresh checkout:

  ```sh
  xcodegen generate
  ```

- Compile the app and test bundle without needing a bootable simulator:

  ```sh
  xcodebuild build-for-testing -project Playloom.xcodeproj -scheme Playloom -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
  ```

- Run the required test lane against the first available iPhone simulator, matching `.github/workflows/ios.yml`:

  ```sh
  playloom_simulator=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next(x["name"] for runtime in d.values() for x in runtime if x["name"].startswith("iPhone")))')
  xcodebuild test -project Playloom.xcodeproj -scheme Playloom -destination "platform=iOS Simulator,name=$playloom_simulator" -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
  ```

- For a targeted test, append `-only-testing:PlayloomTests/<TestClass>/<testMethod>` to that `xcodebuild test` command. `RuntimeIntegrationTests` owns the real `WKWebView` runtime acceptance; `VerticalSliceTests` deliberately injects a fake runtime check to keep orchestration tests deterministic.
- There is no separate lint, format, or type-check task. Compilation with the settings in `project.yml` is the type/concurrency gate. Documentation validation and repository-specific prohibited-name/secret scans live in `.github/workflows/docs.yml` and `.github/workflows/ios.yml`; use those shell steps rather than inventing a local wrapper.

## Boundaries and invariants

- `Generation/GenerationModel.swift` coordinates provider output, candidate staging, runtime validation, and promotion to the playable in-memory state. A failed generation or edit must preserve the last passing project/session.
- `Projects/GameProject.swift` is the current generated-file trust boundary (required files, safe relative paths, allowed types, and total size). `Projects/ProjectWorkspace.swift` stages UUID candidates under a temporary `PlayloomWorkspace`; the durable revision library and import/export described in roadmap docs are not implemented yet.
- Treat all generated HTML/JavaScript as untrusted. `Runtime/GameRuntimeSession.swift` owns the isolated `WKWebView`, typed bridge, input/restart probes, and navigation policy. Generated content must never receive credentials, provider headers, arbitrary native calls, cross-project paths, or undeclared network access.
- The universal floor is six game checks—load, JavaScript errors, non-blank canvas, advancing heartbeat, fresh input, and restart—plus WebKit bridge readiness as a separate prerequisite/report label. Project or model output cannot disable or weaken it. Update `UniversalRuntimeChecker.swift` and `RuntimeIntegrationTests.swift` together when changing this contract.
- Provider credentials belong only in `APIKeyStore`/Keychain. Persist or render curated status only; never log or store prompts, source, raw provider responses, credentials, or chain-of-thought as diagnostics/activity.

## Generated, vendored, and live-only files

- `Playloom/Resources/Phaser/phaser.min.js` is vendored third-party runtime code. Do not modify it as application source; an intentional upgrade must keep its adjacent `LICENSE` and licensing/export obligations intact.
- `Playloom/Resources/live-smoke-key.txt` is an ephemeral credential file created only by the manually dispatched `live-smoke` workflow. Never create or commit it locally. The live test skips when it is absent; normal tests must not contact a provider.
- `PLAYLOOM_ARTIFACT_DIR` makes `ProjectWorkspace` copy every staged candidate to that directory for CI artifact upload. Leave it unset for ordinary local tests unless retained generated projects are intentionally needed.

## Read before changing

- Runtime checks, WebKit isolation, or provider data flow: `docs/ARCHITECTURE.md`, `docs/SECURITY.md`, and `docs/adr/004-programmatic-floor.md`.
- Project persistence, revisions, import, or export: `docs/PROJECT_FORMAT.md` and `docs/adr/006-app-private-canonical.md`.
- Recovery, retries, diagnostics, or promotion: `docs/adr/008-diagnostic-repair-and-blind-resampling.md` and `docs/milestones/M2-reliability.md`.
- Treat milestone documents as staged requirements, not proof that later functionality already exists. `CONTRIBUTING.md` still says the repository is specification-only; current source, tests, README status, and completed M1 document supersede that stale sentence.

## Completion checks

- Regenerate after `project.yml` changes and run `build-for-testing`.
- Run targeted tests while iterating, then run the full simulator test lane before handing off any implementation change.
- Changes to `Runtime/`, generated-project validation, or the WebKit bridge must run `RuntimeIntegrationTests` on a simulator; orchestration-only tests are not sufficient.
- Simulator success proves automated WebKit integration but not physical-device touch, lifecycle, performance, orientation, or visual acceptance. Report those separately unless they were actually exercised on an iPhone or iPad.
