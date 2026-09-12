# Playloom Product Specification

## Product statement

Playloom lets someone describe a small 2D game in chat, play a generated version on the same device, then keep refining it in plain language. It handles the unglamorous loop too: package the files, launch the game, catch runtime failures, inspect a screenshot, and ask the model to fix what broke.

## Principles

1. **Playable beats impressive-looking source.** A generation is not done until the runtime checks pass.
2. **The project belongs to the user.** Every game is an ordinary folder of web files and assets.
3. **Private by default.** Games stay on-device unless the user explicitly exports or publishes one.
4. **Bring your own access.** Playloom never resells tokens and does not require a Playloom account.
5. **Constrain generation, not creativity.** The generator may write HTML, CSS, JavaScript, JSON, and assets inside one project. It may not create executable native code.
6. **Useful without a premium image API.** System shapes and Image Playground provide a no-extra-cost asset path on supported devices.

## Target user

A single maker who wants to sketch arcade, puzzle, platform, or toy-like 2D games without setting up a development environment. v1 optimizes for one person, one device, and short games rather than teams, marketplaces, or long-running live services.

## Core journey

1. Start a project and describe a game.
2. Choose a text model connection and, optionally, a different image model.
3. Playloom asks only the questions that block a useful first build.
4. The model returns a project patch against a constrained template.
5. Playloom validates paths and files, loads the game locally, runs checks, and captures a screenshot.
6. If checks fail, Playloom sends a bounded repair brief to the model and reruns the checks.
7. The user plays the result, asks for changes, rolls back a bad revision, exports the folder, or publishes a static build.

## v1 scope

### Included

- iPhone and iPad SwiftUI app.
- Text chat with project-aware history and explicit generation progress.
- New game, open game, duplicate, rename, delete, import, and export.
- Phaser template and a small plain-Canvas template.
- Touch, keyboard-emulation controls, pause, restart, mute, and orientation metadata.
- Revision snapshots and rollback.
- Provider connections:
  - ChatGPT Plus/Pro through device-direct OAuth and the Codex backend.
  - OpenAI API key.
  - OpenRouter API key.
  - OpenCode Go API key.
- Independent text and image provider selection.
- Image Playground assets on devices where Apple exposes the feature.
- Programmatic runtime checks on every generated revision.
- Optional screenshot review by a vision-capable model.
- Explicit publish and unpublish to a thin static host.
- Local usage estimates when providers return usage data. No Playloom billing.

### Excluded

- A Playloom login, cloud sync, billing, subscriptions, or token resale.
- A required remote generation server or remote OpenCode process.
- Multiplayer servers, leaderboards, accounts inside generated games, or arbitrary network access.
- An in-app public marketplace or game discovery feed.
- Generated Swift, dynamic native-code loading, or native plug-ins.
- SpriteKit execution in v1.
- Android, macOS, or web authoring clients.
- Guaranteed Image Playground availability on every supported OS/device/region.

## Functional requirements

### Project creation and chat

- A project begins from a short prompt or a bundled starter.
- Chat records intent and revision references; large files do not get copied into every message.
- Before generation, the UI shows the selected providers and whether the request may incur provider charges.
- Generation may be cancelled. The last passing revision remains playable during a failed generation.
- Model output is applied through a typed patch protocol, never by allowing a model direct filesystem access.

### Runtime

- Game files are served from a project-scoped custom URL scheme or read-only local server abstraction, not the public internet.
- A strict content security policy blocks unapproved remote scripts, frames, storage, navigation, downloads, and popups.
- The bridge exposes a small versioned message surface for readiness, logs, metrics, assertions, and user controls.
- A watchdog detects failure to boot, uncaught errors, runaway reloads, and a stalled main loop.
- The user can inspect a concise run report without seeing hidden credentials or full model prompts.

### Self-check and repair

Every candidate revision must clear a programmatic floor:

- schema and file validation;
- no paths outside the project root;
- no disallowed URLs or APIs;
- JavaScript parse/load success;
- no uncaught console errors during the test window;
- a ready signal before timeout;
- non-blank rendered frames measured from pixels, not DOM presence alone;
- at least one declared entity and meaningful entity-motion/state assertions where the template expects them;
- a successful reset/restart assertion.

When configured, vision review receives a screenshot plus a narrow rubric: visible game scene, legible UI, clipping, obvious placeholder art, and whether the scene matches the prompt. It must not replace the programmatic floor.

A failed candidate gets a structured repair packet containing relevant source slices, sanitized logs, failed assertions, and screenshot findings. v1 allows a small fixed repair budget, default two attempts. It never loops without a visible bound. If repair fails, Playloom restores the previous passing revision and explains the remaining failures.

### Assets

- The text model writes an asset manifest before assets are generated.
- The user can choose Image Playground, a configured image provider, generated vector/shape placeholders, or imported files.
- Text and image providers are selected separately.
- Asset prompts describe one isolated subject, viewpoint, palette, dimensions, and transparency needs.
- Generated images are normalized into project assets with stable logical names and provenance metadata.
- Playloom can regenerate one asset without rebuilding the whole game.

### Export and sharing

- Export produces the canonical project folder or a ZIP with no credential, OAuth token, private prompt history, or device path.
- A built project opens as static content without Playloom-specific infrastructure where browser capabilities permit.
- Publish is an explicit action with a preview of the files and generated public URL.
- The host accepts immutable static bundles, returns a deployment identifier, and supports unpublish. It does not proxy model calls or become an app dependency.

## Provider experience

`CredentialProvider` hides whether access is a subscription OAuth session or API key. `ModelProvider` exposes model discovery, text generation, optional structured output, optional image generation, usage metadata, and cancellation. Capabilities are discovered and cached, not inferred from model names alone.

ChatGPT subscription support is ported device-direct into Swift: Authorization Code + PKCE, token exchange/refresh, account selection where required, and Codex backend requests occur on the phone. No token or request passes through Playloom infrastructure. Because this is not a stable public third-party API contract, feasibility and release compatibility are explicit gates in Milestones 1 and 6.

OpenCode Go is a direct API-key provider. It is not a local or hosted OpenCode server. OpenRouter is the catch-all for models that are not first-class providers.

## Non-functional requirements

- **Privacy:** local-first projects; no analytics SDK in the first release; diagnostics are user-exported.
- **Security:** Keychain-backed secrets, ephemeral injection into requests, log redaction, strict web sandbox.
- **Reliability:** atomic revisions, deterministic validation before model-based review, recovery after app termination.
- **Performance:** playable preview should not block the main thread; incremental patches avoid resending unchanged assets.
- **Accessibility:** Dynamic Type in the shell, VoiceOver labels, reduced-motion shell behavior, and generated-game accessibility guidance.
- **Cost visibility:** warn before a provider request, show model and estimated/returned usage, and enforce user-set per-generation limits when the provider supports them.

## Success measures

For an internal test set of at least 20 prompts across four game types:

- at least 80% produce a passing, playable first revision within the repair budget;
- 100% of accepted revisions pass the programmatic floor;
- no secret appears in project export, logs, screenshots, or publish bundles;
- a passing project can be exported, deleted from Playloom, re-imported, and played unchanged;
- a published build runs with the Oracle VM unavailable except for the static host under test;
- no app workflow requires a Playloom account or paid Playloom service.

## Release posture

The first public release is free if shipped. Provider charges are between the user and the provider. App Store review, ChatGPT subscription compatibility, Image Playground entitlement/availability, and generated-content safety must all pass the release milestone; none is assumed from a prototype.
