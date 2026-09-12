# Milestone 5: Providers

## Outcome

Complete and harden the stable v1 provider set after the product loop is reliable.

## Deliverables

- Stable OpenRouter, OpenAI, and OpenCode Go API-key adapters.
- Model/capability discovery, normalized streaming/errors/usage, cancellation, connection health, and per-generation limits.
- Provider contract suite and fixtures for unsupported structured output and malformed/empty responses.
- Clear UI for selected provider/model and possible provider charges.
- Experimental ChatGPT adapter only if Milestone 0 found it safe and worth maintaining; otherwise a documented deferred state.

## Tests

- Shared adapter suite for auth expiry, rate limits, empty output, bad JSON, cancellation, usage, capability mismatch, and model removal.
- Keychain create/replace/disconnect and log redaction.
- Required CI uses protocol fakes; protected opt-in smoke lane checks all stable live adapters.
- Experimental ChatGPT tests are isolated and cannot break stable-provider builds when the feature is disabled.

## Acceptance

- Each stable provider can independently generate and patch the vertical-slice game.
- OpenCode Go is direct API access, not a local or remote OpenCode server.
- Playloom works fully with ChatGPT experiment absent.
- Required CI is green on `main`.
