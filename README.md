# Playloom

Playloom is an iPhone and iPad app that turns a chat prompt into a small, playable 2D game. It generates a portable HTML/JavaScript project, runs it locally in a sandboxed `WKWebView`, creates or imports sprites, and checks the result before handing it back to the player.

Playloom is a personal project. If it is published, the app is free. Users bring their own model subscription or API key. Playloom has no account system, billing service, token markup, or required backend.

> Status: specification only. There is no app code yet.

## What is locked

- Native SwiftUI shell for iPhone and iPad.
- Generated games use Phaser or plain Canvas in a local `WKWebView`.
- Generated Swift is never compiled or run. A future native runtime may interpret a declarative `game.json` through SpriteKit.
- Launch providers: ChatGPT Plus/Pro subscription, OpenAI API key, OpenRouter API key, and OpenCode Go API key.
- Credentials and OAuth tokens stay in the iOS Keychain and are sent only to the selected provider.
- Image Playground is the free default asset path on supported devices. A separately selected image model may generate sprites.
- Every generated game gets programmatic checks. An optional cheap vision model reviews a screenshot when available.
- Projects are folders that can be exported without Playloom. Sharing publishes static game files to a thin host controlled by the project owner.

## Documentation map

- [Product specification](docs/PRODUCT_SPEC.md)
- [Architecture map](docs/ARCHITECTURE.md)
- [Security and privacy model](docs/SECURITY.md)
- [Portable project format](docs/PROJECT_FORMAT.md)
- [Milestone index](docs/milestones/README.md)
- [Decision records](docs/adr/README.md)
- [Research sources](docs/SOURCES.md)

## Delivery rule

Milestones merge in order. A milestone is complete only when its acceptance criteria are demonstrated and the required GitHub Actions run is green on `main`. A later milestone cannot be used to waive an earlier gate.

## License

[GPL-3.0](LICENSE)
