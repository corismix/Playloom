# Architecture Map

## v1 system boundary

```text
┌──────────────────────────── iPhone / iPad ────────────────────────────┐
│ One SwiftUI app target                                                │
│                                                                       │
│ App UI ── Generation coordinator ── Provider registry                 │
│   │              │                     ├─ OpenRouter key              │
│   │              │                     ├─ OpenAI key                  │
│   │              │                     ├─ OpenCode Go key             │
│   │              │                     └─ ChatGPT experiment          │
│   │              │                                                   │
│   │              ├─ Patch validation ── App-private project store    │
│   │              └─ Runtime checks                                  │
│   │                          │                                        │
│   └──────────── sandboxed WKWebView + vendored Phaser                │
│                              │                                        │
│             console / heartbeat / pixels / input / assertions         │
│                                                                       │
│ Files import/export only             iOS Keychain                    │
└───────────────────────────────────────────────────────────────────────┘
                 │ direct HTTPS to selected provider
                 ▼
          Provider-owned endpoint
```

There is no Playloom backend in v1. Public static sharing and vision evaluation are later work.

## Source organization

Start with one app target. Clean folders and protocols provide boundaries without premature package or target overhead:

```text
Playloom/
├── App/          SwiftUI entry, navigation, feature composition
├── Projects/     canonical app-private storage, formats, revisions, import/export
├── Providers/    credentials, adapters, normalized provider events
├── Runtime/      WKWebView sandbox, bridge, Phaser host, checks
├── Generation/   plans, prompts, typed patches, orchestration, repair
└── Assets/       manifests, procedural assets, imported images, later generators
```

Tests mirror these folders. Split a package or target only when there is a measured build, reuse, isolation, or ownership benefit.

## Core responsibilities

### App

SwiftUI library, chat, activity, preview, provider settings, check reports, import/export, and accessibility. iPhone switches between focused Chat and Play surfaces; iPad may use `NavigationSplitView` for chat and live play together. Activity/assistant summaries use pinned Textual Markdown rendering. It owns presentation, not raw credentials or project mutation, and never renders raw chain-of-thought.

### Projects

The app-private container is canonical. Imports copy and validate external content into a new local project. Exports write an immutable snapshot. Live editing of a Files location is forbidden in v1 because coordination, security-scoped URLs, partial writes, and external edits would weaken revision guarantees.

Candidate changes stage separately. Reliability adds a durable single-project run journal and minimal immutable passing revisions before polished progress claims. Each edit is pinned to a base revision. Promotion atomically commits candidate files, report, immutable revision, and the current pointer; a stale completion cannot promote. Restore creates a new revision derived from an older snapshot. The projects milestone expands these primitives into the library, full history, migration, and import/export.

### Providers

```swift
protocol CredentialProvider {
    var kind: CredentialKind { get } // apiKey | experimentalSubscription
    func authorize(_ request: URLRequest) async throws -> URLRequest
    func disconnect() async throws
}

protocol ModelProvider {
    func capabilities() async throws -> ProviderCapabilities
    func generate(_ request: GenerationRequest)
      -> AsyncThrowingStream<GenerationEvent, Error>
}
```

Interfaces are illustrative. Persistent secrets stay behind the credential object. Stable adapters are OpenRouter, OpenAI, and OpenCode Go. The ChatGPT adapter is experimental and compiled/flagged so it can be absent without affecting projects or stable providers.

### Generation

The UI consumes typed, replayable `GenerationEvent` values from a generation orchestrator rather than inferring progress from scalar status text. Events include stable project/run/candidate/base-revision IDs and observed transitions such as stage started, provider output received, candidate staged, check finished, resample started, revision promoted, cancelled, interrupted, and failed. Persist curated event facts and outcomes, never provider reasoning content.

The vertical-slice state machine is intentionally short:

```text
idle → plan → generate Phaser project → validate → launch → universal checks
     → accepted → chat edit → generate patch → validate → reload → checks
     → accepted | failed (keep prior passing state)
```

Reliability extends it with a durable run journal, staged revisions, bounded repair, rollback, cancellation, and crash recovery. Background URL-session task identifiers, response/body locations, and run metadata are persisted so an OS relaunch can reattach; in-memory continuations alone are insufficient. Suspension, OS relaunch, user force-quit, and foreground validation are distinct lifecycle states. The model proposes typed operations against an allowlist; it never owns the filesystem.

### Runtime

A project-scoped `WKWebView` loads only staged local content and a vendored Phaser build. The bridge is small and typed. Generated code receives no credentials, provider headers, arbitrary native calls, sensors, or cross-project paths. Navigation, popups, downloads, and undeclared network access are denied.

### Runtime checks

Two layers stay explicit:

**Universal floor, owned by Playloom**
- document/scene loads;
- no fatal JavaScript or console error through the end of active probes;
- canvas is not blank;
- heartbeat frame values advance;
- fresh operation-scoped synthetic/declared input reaches the game;
- fresh operation-scoped restart returns to ready.

Universal success is presented as “Basic runtime passed,” not proof that requested mechanics work. The bridge is an infrastructure prerequisite in addition to the six checks. Event waits match only evidence recorded after the current operation begins; stale acknowledgements never satisfy a later probe.

**Game-specific assertions, produced from the game plan**
- planned player action changes position/state;
- score or another planned value changes;
- required entities/transitions appear;
- planned win/lose/progression behavior is observable.

The user's verbatim prompt and the derived typed game plan remain separate. The plan defines the core loop, controls, entities, win/lose conditions, and evidence-backed done-when checks. Every runtime-state field must be consumed by a check; state, screenshot, and input-trace evidence are selected by claim type.

Failures are classified before recovery as model output, game runtime, validator/harness, or platform/lifecycle. Generated code is never repaired to mask harness or platform faults, and assertions are never weakened just to pass.

A game plan cannot disable the universal floor. The vertical slice lands the universal checks first; the reliability milestone adds richer plan-generated assertions and bounded, failure-classified recovery per ADR-008.

### Assets

v1 baseline uses procedural Phaser geometry and user-imported images. The asset manifest uses stable logical IDs. Remote image adapters and Image Playground are later experiments behind availability/capability checks. They cannot become prerequisites for playable generation.

## Trust boundaries

| Boundary | Untrusted input | Enforcement |
|---|---|---|
| Import → app store | all imported files | schema, path, size and type validation; copy, never live edit |
| Model → candidate | every response and patch | typed patch parser, staging, allowlist |
| Game → app | all project JavaScript | isolated web view, typed bridge, no secret API |
| App → provider | provider response/catalog | TLS, adapter validation, redaction |
| Game plan → checks | generated assertions | constrained assertion schema; universal floor cannot be weakened |

## Later architecture

- **Assets:** remote image provider and optional Image Playground.
- **Providers:** more models after the three stable adapters; experimental ChatGPT only if the spike is safe.
- **Evaluation:** optional vision critic after deterministic checks prove useful.
- **Sharing:** thin static host after project/export reliability and Guideline 4.7 work.
- **Native runtime:** a future SpriteKit interpreter may consume versioned `game.json`; generated Swift remains forbidden.
