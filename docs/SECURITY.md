# Security and Privacy Model

## Goals

- Generated/imported JavaScript cannot reach credentials, privileged native APIs, or another project.
- Credentials leave the device only in requests to the provider they authorize.
- Failed candidates cannot replace a passing game.
- Imports and exports cannot bypass app-private canonical storage.

## Credentials

Stable API keys and any experimental OAuth material live in iOS Keychain. Secrets never enter project files, `UserDefaults`, logs, screenshots, clipboard history, diagnostics, or exports. Provider code authorizes a request without exposing persistent raw values to feature folders. Disconnect deletes the relevant items and cached state.

Experimental ChatGPT login, if retained after the risk spike, uses `ASWebAuthenticationSession`, Authorization Code + PKCE, state verification, exact callbacks, and device-side exchange. No Playloom relay is allowed. Removing the experiment must not affect stable API-key providers.

## Web runtime

Generated content is untrusted. The dedicated project `WKWebView` uses a typed, versioned bridge; blocks navigation, popups, downloads, sensors, clipboard, cross-project files, and undeclared network; and receives no credential/provider header. Runtime libraries are pinned and vendored. Process failure discards the candidate web view.

Milestone 0 tests whether these controls and universal instrumentation are technically sufficient and assesses how Guideline 4.7 affects the architecture. App Store classification is not treated as a security control or assumed approval.

## Model boundary

Only required project context, user instruction, structured game plan, and sanitized run report reach the selected model. Model output cannot change credentials, weaken universal checks, approve itself, or trigger export/publication. Typed patch validation rejects traversal, unexpected types/sizes/origins, and secret-like data.

## Storage and export

App-private storage is canonical. Import copies through validation. Export constructs a new snapshot from an allowlist. Tests seed canary secrets and prove they do not survive diagnostics or export. External Files changes never mutate an open project.

## Supply chain and licensing

Dependencies are pinned and inventoried. Playloom uses MIT; runtime/export templates use MIT or explicit CC0. CI checks template notices and rejects GPL/AGPL dependencies from export fixtures unless a future reviewed decision deliberately changes policy.

## Release blockers

- Secret appears in logs, app files outside Keychain, diagnostics, or export.
- Generated content reaches undeclared native methods, outbound origins, or another project.
- Universal checks can be weakened by model/project data.
- Import can become a live externally mutable source.
- Failed candidate can replace the last passing revision.
- Provider credentials transit a Playloom-controlled server.
- Current Guideline 4.7 requirements lack a recorded classification and architecture response before public distribution.
