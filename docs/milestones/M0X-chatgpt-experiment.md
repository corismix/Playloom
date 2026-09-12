# Milestone 0X: Experimental ChatGPT/Codex OAuth

## Status

Parallel and non-gating. M1 must not import, link, configure, or depend on this experiment. It may be paused or removed without changing the stable API-key product path.

## Outcome

Determine whether ChatGPT Plus/Pro can be used safely from iOS through device-direct OAuth and Codex backend requests, without a Playloom relay or remote OpenCode server.

## Deliverables

- Isolated Swift spike using `ASWebAuthenticationSession` and Authorization Code + PKCE.
- Device-side token exchange/refresh and one Codex backend request.
- Compatibility/security record against the current open-source Codex client.
- Expected-origin network evidence and Keychain storage design.
- Go/defer/drop recommendation and clean feature-disable path.

## Tests

- PKCE verifier/challenge, OAuth state, exact callback, refresh serialization, disconnect, redaction, and expected-origin checks.
- Protected opt-in live test only; no consumer token in required CI.

## Acceptance

- Findings and recommendation are documented.
- Any code remains isolated from M1 and stable provider protocols.
- A failure or provider change does not block Playloom.
- Its own CI is green, but M1 never waits for M0X.
