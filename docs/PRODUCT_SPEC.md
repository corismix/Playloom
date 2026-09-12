# Playloom Product Specification

## Product statement

Playloom lets someone describe a small 2D game, play the generated version on the same device, and refine it in chat. Its differentiator is the closed loop: generate a constrained project, launch it, measure whether it works, and refuse to present a broken candidate as done.

## Principles

1. **Playable beats plausible source.** A candidate must pass programmatic checks.
2. **Start with one complete path.** Prove prompt-to-edit before broad provider, asset, or sharing work.
3. **Private by default.** Projects stay on-device unless explicitly exported.
4. **Bring your own access.** Playloom never resells tokens and needs no account.
5. **Constrain generation.** Models write web project patches, never executable native code.
6. **Projects remain portable.** The app's private store is canonical; import/export uses an open folder format.

## v1 user

One maker sketching short arcade, puzzle, platform, or toy-like 2D games without setting up a development environment. v1 does not optimize for teams, a marketplace, multiplayer services, or public publishing.

## v1 vertical slice

1. Create a project and describe a game.
2. Choose one configured stable text provider.
3. Generate a Phaser project from a pinned starter.
4. Validate files and launch the candidate in a sandboxed `WKWebView`.
5. Run universal checks: load, no JavaScript crash, non-blank rendering, live heartbeat, input path, and restart.
6. Run game-specific assertions derived from the approved game plan when present.
7. Promote the candidate only when required checks pass.
8. Play the game, request one chat edit, apply a typed patch, and reload.

## v1 scope

### Included

- Native SwiftUI shell for iPhone and iPad.
- One app target organized into `App`, `Projects`, `Providers`, `Runtime`, `Generation`, and `Assets` folders.
- Phaser-only generated runtime with a vendored, pinned engine version.
- Project chat, initial generation, one or more edits, constrained patching, and reload.
- Stable API-key providers: OpenRouter, OpenAI, and OpenCode Go. The vertical slice may begin with one and adds the other stable adapters later in the roadmap.
- API keys in iOS Keychain.
- Universal programmatic runtime floor on every candidate.
- Game-specific assertions generated from a game plan, kept separate from the universal floor.
- Bounded repair loop, rollback, revisions, app-private persistence, and Files import/export as reliability/projects milestones mature.
- Long-generation UX and lifecycle resilience: real stage progress, provider streaming where available, honest keep-open guidance when iOS suspension would stop work, interrupted-request recovery, and temporary idle-timer suppression while foreground generation runs.
- Procedural shapes and user-imported images as the free asset baseline.
- Local usage estimates where providers return usage.

### Experimental or postponed

- ChatGPT Plus/Pro subscription access through device-direct OAuth and the Codex backend. It is a risk spike, not promised v1 functionality.
- Image Playground. It is an optional asset experiment, not the default or a release dependency.
- Vision-model screenshot evaluation. Postponed until after deterministic checks and the edit loop are reliable.
- Public static hosting, publish/unpublish, sharing infrastructure, and App Store submission. These are the final roadmap stage.
- Plain Canvas runtime, SpriteKit runtime, and declarative `game.json` execution.

### Excluded

- Playloom accounts, cloud sync, billing, subscriptions, or token resale.
- A required generation backend, model proxy, or remote OpenCode process.
- Generated Swift or dynamically loaded native code.
- Multiplayer servers, leaderboards, or accounts inside generated games.
- Android, macOS, or web authoring clients.

## Requirements

### Generation and edits

- The model receives the game plan, manifest, relevant files, user instruction, and sanitized check report only.
- Output uses a versioned typed patch protocol. The model never gets direct filesystem access.
- Paths, file types, sizes, network origins, and secret-like content are validated before launch.
- Generation and patching are cancellable.
- A failed candidate never replaces the current passing version.

### Runtime validation

Universal checks apply to every game and are owned by Playloom:

- the page and Phaser scene load before timeout;
- no uncaught exception, unhandled rejection, or fatal console error occurs;
- the canvas contains meaningful non-background pixels;
- the animation heartbeat remains alive;
- the declared input probe reaches the game;
- restart returns the runtime to a ready state.

Game-specific checks come from the structured game plan and vary by game:

- a player can move or otherwise respond to intended input;
- score, health, inventory, timer, or state changes under a declared scenario;
- expected entities appear or transitions occur;
- win, lose, reset, or progression rules produce observable state.

Game-specific checks may refine acceptance but cannot weaken the universal floor. Early vertical-slice candidates may have only the universal set. Reliability work adds the plan-generated set and bounded failure-classified recovery: diagnostic repair packets for structural/crash evidence and blind resampling for logic/behavior failures.

### Projects and storage

- App-private storage is the only live source of truth in v1.
- The app imports a copy from Files and exports a snapshot to Files; it never edits a Files folder in place.
- Candidate writes are staged and promoted atomically.
- Revisions and rollback are added before broad asset/provider work.
- Export excludes credentials, OAuth material, private logs, and device paths.

### Providers

`CredentialProvider` hides whether access is an API key or experimental subscription session. `ModelProvider` normalizes model capability, generation, streaming, cancellation, usage, and errors.

Stable v1 adapters are OpenRouter, OpenAI, and OpenCode Go API keys. OpenCode Go is a direct provider, not an OpenCode server. OpenRouter is the catch-all.

ChatGPT subscription support remains an experiment: Authorization Code + PKCE, token exchange/refresh, and Codex backend calls would occur on the phone, with no Playloom relay. The risk spike may prove or reject it without changing the stable product path.

### Assets

The free baseline is procedural Phaser geometry/simple generated SVG where safe, plus user-imported images. An asset manifest gives files stable logical names. Remote image providers and Image Playground arrive only after the core loop and projects are reliable. Text and image provider selection stays separate.

## Feasibility gates

Before the vertical slice, required Milestone 0 answers two risks:

1. Can the required WebKit sandbox and runtime instrumentation work on target devices?
2. Does the current App Store Guideline 4.7 create an obvious reason not to build the local slice now, or an architectural choice we would regret later? This is a lean go/change/stop assessment, not legal certainty.

Milestone 0X may test ChatGPT subscription OAuth/Codex access in parallel. M1 never depends on it, and a negative result only drops the experiment. Public distribution still gets a fuller current review in the final sharing/App Store milestone.

## Success measures

For an internal set of at least 20 prompts across four simple game types:

- every accepted candidate passes the universal floor;
- at least 80% become playable within the bounded repair budget by the reliability milestone;
- prompt → playable → chat edit → patched reload completes end to end;
- a failed patch leaves the prior game playable;
- no secret appears in project files, diagnostics, or export;
- exported projects carry no Playloom copyleft obligation.

## Release posture

If published, the app is free. Provider charges remain between the user and provider. Stable API-key adapters are sufficient for the product to exist. ChatGPT subscription access, Image Playground, vision evaluation, and public sharing are optional later capabilities, not launch blockers.
