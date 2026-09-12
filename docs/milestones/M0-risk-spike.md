# Milestone 0: Risk Spike

## Outcome

Answer the three questions that could force a product or architecture change before building the vertical slice: WebKit containment/instrumentation, App Store Review Guideline 4.7, and experimental ChatGPT subscription access.

## Deliverables

### WebKit sandbox spike

- Small iPhone/iPad SwiftUI test shell with one app target and folders matching the planned source layout.
- Vendored Phaser fixture loaded locally in `WKWebView`.
- Denied navigation/popups/downloads and an outbound-network allowlist defaulting to none.
- Typed readiness, console, heartbeat, input-probe, restart, and pixel/snapshot instrumentation.
- Findings for WebGL canvas capture and process crash/recovery on target OS/device matrix.

### App Store Guideline 4.7 feasibility

- Quote/link the current guideline and record the date reviewed.
- Written classification analysis: whether locally generated HTML5 games are mini apps/mini games under 4.7, what review may expect, and which conclusions remain uncertain.
- Requirements matrix covering software not embedded in the binary, content/indexing or catalog expectations, age/content controls, privacy, native API exposure, payments, user reporting/moderation if sharing ships, and any other current subclauses.
- Architecture impact assessment for local-only generation, imports, static sharing, runtime bridge, manifests, review metadata, and potential limits on downloading/executing content.
- A go/change/stop recommendation for private use, TestFlight, and public App Store release. When text is ambiguous, obtain qualified review or written platform clarification rather than guessing.

### Experimental ChatGPT subscription spike

- Device-direct `ASWebAuthenticationSession` + Authorization Code/PKCE proof in Swift.
- Device-side token exchange/refresh and one Codex backend request; no relay or OpenCode server.
- Compatibility/security record against the current open-source Codex client.
- Clean feature-disable path if the flow is unsafe, disallowed, or unstable.

## Tests

- Sandbox escape attempts, disallowed URLs, bridge fuzzing, console capture, blank render, heartbeat loss, input probe, restart, and content-process termination.
- PKCE verifier/challenge, state/callback validation, refresh serialization, redaction, disconnect, and expected-origin network test.
- App Store requirements matrix reviewed against the current official guideline page and archived in the milestone evidence.

## Acceptance

- WebKit can enforce and observe the universal v1 runtime floor on representative target devices, or the architecture is revised before proceeding.
- Guideline 4.7 has an explicit classification/risk decision and concrete architecture requirements, not a late release assumption.
- ChatGPT feasibility has a documented result. Failure disables the experiment and does not block Playloom.
- Required CI is green on `main`.
