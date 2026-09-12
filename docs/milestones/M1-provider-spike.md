# Milestone 1: Provider and Credential Feasibility

## Outcome

Prove every v1 access path from an iOS test shell before product workflows depend on it.

## Deliverables

- `CredentialProvider` and `ModelProvider` contracts with fake adapters.
- Keychain store with create, read-through authorization, replace, and disconnect behavior.
- ChatGPT subscription spike in Swift using `ASWebAuthenticationSession`, PKCE, device-side token exchange/refresh, and direct Codex backend request. No relay.
- Direct OpenAI, OpenRouter, and OpenCode Go API-key adapters.
- Model/capability discovery with explicit unsupported states.
- Streaming, cancellation, normalized errors, provider request IDs, and usage metadata.
- Compatibility note pinning the observed Codex auth/backend contract and a kill-switch behavior that disables this connection cleanly if it changes.

## Tests

- Deterministic unit tests for PKCE/state/callback validation and serialized refresh.
- Keychain tests on simulator/device test host; secrets absent from logs and persisted app files.
- Adapter contract suite driven by fixtures for streaming, rate limits, auth expiry, malformed payloads, empty output, cancellation, and unavailable capabilities.
- Opt-in live smoke tests for all four connections, using CI secrets only in a protected lane; required CI uses local protocol fakes.
- Network capture or mock proves ChatGPT tokens go only to expected OpenAI origins and never to an app-owned host.

## Acceptance

- A user can connect and disconnect each provider in the spike shell.
- One short text response succeeds through each live adapter in the documented manual/protected test.
- ChatGPT access works from the phone without an OpenCode server or any Playloom server.
- If ChatGPT compatibility cannot be proved safely, implementation stops for a product decision; it is not silently replaced with API-key access.
- Required CI is green on `main`.
