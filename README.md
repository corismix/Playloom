# Playloom

Playloom is an iPhone and iPad app that turns a chat prompt into a small, playable 2D game. It generates a Phaser project, checks that it works, runs it locally in a sandboxed `WKWebView`, and lets the maker refine it through chat.

Playloom is a personal project. If it is published, the app is free. Users bring their own API access. Playloom has no account system, billing service, token markup, or required backend.

> Status: specification only. There is no app code yet.

## v1 vertical slice

1. Enter a prompt and select one stable API-key provider.
2. Generate a Phaser HTML/JavaScript project.
3. Check that it boots, has no console errors, renders a non-blank canvas, and keeps a live heartbeat.
4. Play it in a local `WKWebView`.
5. Ask for an edit in chat.
6. Apply a constrained patch and reload.

The programmatic self-check is part of the first usable slice, not later polish.

## Locked direction

- Native SwiftUI shell for iPhone and iPad; generated games run in Phaser inside `WKWebView`.
- Generated Swift is never compiled or run. A later native runtime may interpret declarative `game.json` through SpriteKit.
- Stable provider path: OpenRouter API key, OpenAI API key, and OpenCode Go API key.
- ChatGPT Plus/Pro access is experimental. Its device-direct OAuth/Codex flow gets a feasibility spike but cannot block Playloom.
- Universal runtime checks are separate from checks generated for a particular game plan.
- App-private storage is canonical. Files is import/export only.
- Procedural shapes and user-imported images are the free asset baseline. Image Playground is experimental.
- Vision evaluation and public publishing are postponed until after the core loop is reliable.

## Documentation map

- [Product specification](docs/PRODUCT_SPEC.md)
- [Architecture map](docs/ARCHITECTURE.md)
- [Security and privacy model](docs/SECURITY.md)
- [Portable project format](docs/PROJECT_FORMAT.md)
- [Milestone index](docs/milestones/README.md)
- [Decision records](docs/adr/README.md)
- [Research sources](docs/SOURCES.md)
- [Licensing policy](docs/LICENSING.md)

## Delivery rule

Milestones merge in order. A milestone is complete only when its acceptance criteria are demonstrated and its required GitHub Actions run is green on `main`.

## License

Playloom is [MIT licensed](LICENSE). Runtime and export templates are also MIT licensed so generated or exported games inherit no copyleft obligation from Playloom. See [Licensing](docs/LICENSING.md).
