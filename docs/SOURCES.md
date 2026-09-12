# Research Sources

Primary references used to shape the specification. These links are constraints and implementation leads, not a substitute for rechecking current terms and APIs during each milestone.

| Topic | Source | Use |
|---|---|---|
| iOS secrets | [Apple: Using the keychain to manage user secrets](https://developer.apple.com/documentation/security/using-the-keychain-to-manage-user-secrets) | Keychain boundary for keys and OAuth tokens |
| Web runtime | [Apple: WebKit](https://developer.apple.com/documentation/webkit) | `WKWebView`, navigation policy, content process and snapshots |
| Browser authentication | [Apple: Authenticating a user through a web service](https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service) | `ASWebAuthenticationSession` login flow |
| On-device images | [Apple: Image Playground](https://developer.apple.com/documentation/imageplayground) | Availability-gated default image path |
| App review | [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) | Generated HTML/game and publication release review |
| ChatGPT auth implementation lead | [OpenAI Codex login source](https://github.com/openai/codex/tree/main/codex-rs/login) | Current PKCE, token exchange, refresh and account behavior to port, with compatibility risk |
| OpenCode Go | [OpenCode Go documentation](https://opencode.ai/docs/go/) | Subscription/API-key provider behavior and supported models |
| OpenCode providers | [OpenCode provider documentation](https://opencode.ai/docs/providers/) | Distinguishes direct provider credentials from running an OpenCode server |
| OpenAI API | [OpenAI API authentication](https://platform.openai.com/docs/api-reference/authentication) | API-key adapter |
| OpenRouter | [OpenRouter API reference](https://openrouter.ai/docs/api-reference/overview) | Catch-all model adapter and catalog |
| Phaser | [Phaser documentation](https://docs.phaser.io/) | Web game runtime and renderer APIs |
| Phaser snapshots | [Phaser renderer snapshot API](https://docs.phaser.io/api-documentation/namespace/renderer-snapshot) | WebGL/canvas capture fallback for self-checking |

## Known uncertainty

ChatGPT consumer-subscription access is implemented by OpenAI's Codex clients but is not treated here as a stable, documented third-party API promise. Milestone 1 must prove the device-direct Swift flow, and the release gate must repeat the compatibility check. Image Playground and screenshot behavior vary by OS, device capability, renderer, and availability; placeholders and renderer-level snapshots are required fallbacks.
