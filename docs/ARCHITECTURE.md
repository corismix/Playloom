# Architecture Map

## System boundary

```text
┌──────────────────────────────── iPhone / iPad ────────────────────────────────┐
│ SwiftUI app                                                                  │
│                                                                              │
│  Project UI ── Generation Orchestrator ── Provider Registry                  │
│      │                  │                    │                                │
│      │                  │                    ├─ ChatGPT OAuth/Codex           │
│      │                  │                    ├─ OpenAI API                    │
│      │                  │                    ├─ OpenRouter                    │
│      │                  │                    └─ OpenCode Go                   │
│      │                  │                                                     │
│      │                  ├─ Patch Validator ── Revision Store                 │
│      │                  ├─ Asset Pipeline ─── Image Playground/image model   │
│      │                  └─ Evaluation Loop                                   │
│      │                              │                                         │
│      └────────────────── Game Runtime (sandboxed WKWebView)                  │
│                                     │                                        │
│                    console / assertions / pixel sample / snapshot            │
│                                                                              │
│  Files app project folders             iOS Keychain (secrets and tokens)     │
└──────────────────────────────────────────────────────────────────────────────┘
                 │ selected provider HTTPS             │ explicit publish
                 ▼                                     ▼
       Provider-owned endpoints              Thin static bundle host
                                             (optional, no model proxy)
```

## Modules

### AppShell

SwiftUI navigation, project library, chat, provider settings, run reports, previews, import/export, publish confirmation, and accessibility. AppShell owns presentation state but not secrets or project mutation.

### ProjectStore

Owns canonical project folders, manifests, revision metadata, atomic staging, rollback, and import/export. A candidate patch is written to a staging revision; only a passing revision becomes `current`.

### GenerationOrchestrator

Runs a state machine:

```text
idle → planning → generating patch → validating → building assets
     → launching → programmatic checks → optional vision review
     → accepted | repairing (bounded) | failed/rolled back
```

The state, attempt count, request identifier, selected models, and candidate revision are persisted so app termination cannot silently accept half-finished work.

### ProviderKit

```swift
protocol CredentialProvider {
    var kind: CredentialKind { get }       // subscription | apiKey
    func authorization() async throws -> ProviderAuthorization
    func disconnect() async throws
}

protocol ModelProvider {
    func capabilities() async throws -> ProviderCapabilities
    func generate(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error>
    func generateImage(_ request: ImageRequest) async throws -> ImageResult
}
```

The interfaces are illustrative, not frozen API. `ProviderAuthorization` is an opaque request signer or short-lived bearer view. Callers never receive refresh tokens or raw stored API keys. Model, endpoint, capability, and credential type are separate values.

Adapters shipped in v1:

- `ChatGPTSubscriptionProvider`: ASWebAuthenticationSession, Authorization Code + PKCE, device-side token exchange and refresh, account metadata, Codex backend transport.
- `OpenAIProvider`: OpenAI API key and current supported generation endpoint.
- `OpenRouterProvider`: OpenRouter API key, model catalog, normalized request/response handling.
- `OpenCodeGoProvider`: OpenCode Go API key and direct provider endpoint.

Provider responses normalize text deltas, structured content, tool/patch payloads, usage, finish reason, provider request ID, and errors. Raw provider payloads are debug-only, redacted, and never included in projects.

### PatchValidator

The model proposes operations against a typed allowlist: create/replace/delete file, update manifest, and declare assets. Validation rejects absolute paths, traversal, symbolic links, oversized files, forbidden file types, secret-like content, disallowed network origins, and changes outside the candidate revision. A deterministic parser checks the project and JavaScript before launch.

### GameRuntime

One ephemeral `WKWebView` per evaluation, backed by a non-persistent website data store where compatible. It loads only staged local project content and bundled runtime libraries. The runtime bridge is versioned and one-way by default; game messages are decoded into known event types.

The page gets no provider credential, OAuth token, Keychain access, arbitrary native method call, camera, microphone, location, contacts, or unrestricted network. Navigation and new-window requests are denied. Production projects vendor a pinned Phaser build instead of loading a CDN at play time.

### EvaluationLoop

Programmatic evaluation is authoritative. It collects:

- boot/readiness timing;
- console and unhandled rejection events;
- animation-frame heartbeat;
- canvas pixel samples at multiple times;
- declared entity counts and state snapshots;
- motion or state deltas;
- restart determinism;
- a `WKWebView` snapshot or renderer snapshot where WebGL capture needs a fallback.

The optional vision evaluator sees only the game screenshot, game brief, and rubric. It does not receive chat history, credentials, provider headers, or unrelated projects. Findings become data in the same bounded repair packet.

### AssetPipeline

Consumes the asset manifest and routes each asset independently. Image Playground is the preferred free option when available. Remote image models use a separately chosen provider and credential. All outputs are decoded, size-limited, stripped of unexpected metadata, normalized, and recorded with origin and prompt provenance. Placeholder vectors keep the game testable when image generation is unavailable.

### ShareClient

Uploads an export-filtered static bundle only after explicit confirmation. The protocol is deliberately small: create deployment, upload immutable files, get status/URL, unpublish. The app remains fully usable when the host is absent. The owner's Oracle VM may host this service but is not an application dependency.

## Data flow: generation

1. AppShell sends a project reference, user instruction, and selected providers to GenerationOrchestrator.
2. ProjectStore creates a candidate revision.
3. The orchestrator builds a minimal context package from the manifest, relevant files, and last run report.
4. ProviderKit signs and sends the request directly from the device.
5. PatchValidator validates and stages returned operations.
6. AssetPipeline resolves new asset declarations.
7. GameRuntime loads the candidate with networking disabled except declared, approved origins (v1 default: none).
8. EvaluationLoop runs the floor, snapshots the canvas, and optionally invokes vision review.
9. A passing candidate is atomically promoted. A failure gets a bounded repair request or rollback.

## Trust boundaries

| Boundary | Trusted input | Untrusted input | Enforcement |
|---|---|---|---|
| User → app | explicit local action | imported project content | schema, file, size and runtime validation |
| Model → project | nothing executable by default | every response and patch | typed patch parser, staging, allowlist |
| Game → native app | versioned known messages | all JavaScript and project assets | isolated web view, decoded bridge, no secret API |
| App → provider | selected request | provider response and catalog | TLS, adapter validation, redaction |
| App → static host | explicit publish bundle | deployment response | export filter, confirmation, host allowlist |
| Vision model | narrow evaluation packet | generated critique | advisory rubric; floor remains deterministic |

## Concurrency and persistence

- One actor owns mutation per project.
- Provider streaming and runtime events use structured concurrency and support cancellation.
- Candidate revisions use write-then-rename semantics.
- The orchestration journal records transitions and is replay-safe.
- Keychain items use stable, app-owned identifiers; project files store only credential aliases.

## Dependency policy

Prefer Apple frameworks for UI, storage, networking, authentication presentation, Keychain, and web runtime. External packages must have an explicit purpose, compatible license, pinned version, and replacement seam. Phaser is vendored per runtime template with its version captured in the project manifest.

## Future native runtime

A later milestone may add a `game.json` schema for scenes, entities, components, input, collisions, audio, and transitions. A SpriteKit interpreter may render that data. The generator still emits data and assets, never Swift. HTML projects remain supported and portable; native interpretation is additive, not a migration requirement.
