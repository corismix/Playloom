# Research Sources

Primary references used to shape the specification. These links are constraints and implementation leads, not a substitute for rechecking current terms and APIs during each milestone.

| Topic | Source | Use |
|---|---|---|
| iOS secrets | [Apple: Using the keychain to manage user secrets](https://developer.apple.com/documentation/security/using-the-keychain-to-manage-user-secrets) | Keychain boundary for keys and OAuth tokens |
| Web runtime | [Apple: WebKit](https://developer.apple.com/documentation/webkit) | `WKWebView`, navigation policy, content process and snapshots |
| Browser authentication | [Apple: Authenticating a user through a web service](https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service) | `ASWebAuthenticationSession` login flow |
| On-device images | [Apple: Image Playground](https://developer.apple.com/documentation/imageplayground) | Availability-gated default image path |
| App review / Guideline 4.7 | [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/#mini-apps-mini-games-streaming-games-chatbots-plug-ins-and-game-emulators) | Milestone 0 classification and architecture feasibility for HTML5 mini-games |
| ChatGPT auth implementation lead | [OpenAI Codex login source](https://github.com/openai/codex/tree/main/codex-rs/login) | Current PKCE, token exchange, refresh and account behavior to port, with compatibility risk |
| OpenCode Go | [OpenCode Go documentation](https://opencode.ai/docs/go/) | Subscription/API-key provider behavior and supported models |
| OpenCode providers | [OpenCode provider documentation](https://opencode.ai/docs/providers/) | Distinguishes direct provider credentials from running an OpenCode server |
| OpenAI API | [OpenAI API authentication](https://platform.openai.com/docs/api-reference/authentication) | API-key adapter |
| OpenRouter | [OpenRouter API reference](https://openrouter.ai/docs/api-reference/overview) | Catch-all model adapter and catalog |
| Phaser | [Phaser documentation](https://docs.phaser.io/) | Web game runtime and renderer APIs |
| Phaser snapshots | [Phaser renderer snapshot API](https://docs.phaser.io/api-documentation/namespace/renderer-snapshot) | WebGL/canvas capture fallback for self-checking |

## Known uncertainty

ChatGPT consumer-subscription access is implemented by OpenAI's Codex clients but is not treated here as a stable, documented third-party API promise. Milestone 0 may prove the device-direct Swift flow, but a negative result drops the experiment rather than blocking the stable API-key product. Image Playground remains an optional experiment because availability varies by OS, device, and region. Procedural shapes and user imports are the asset baseline. Guideline 4.7 is reviewed in the first risk spike and revalidated before public distribution.
