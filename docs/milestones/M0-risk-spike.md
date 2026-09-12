# Milestone 0: Risk Spike

## Outcome

Answer the two questions that could force an immediate product or architecture change before building the vertical slice: WebKit containment/instrumentation and a lean App Store Review Guideline 4.7 assessment.

## Deliverables

### WebKit sandbox spike

- Small iPhone/iPad SwiftUI test shell with one app target and folders matching the planned source layout.
- Vendored Phaser fixture loaded locally in `WKWebView`.
- Denied navigation/popups/downloads and an outbound-network allowlist defaulting to none.
- Typed readiness, console, heartbeat, input-probe, restart, and pixel/snapshot instrumentation.
- Findings for WebGL canvas capture and process crash/recovery on target OS/device matrix.

### Lean App Store Guideline 4.7 assessment

This is a product/architecture check, not a request for legal certainty. Record the current official guideline link and answer:

1. **Can Playloom build the local-only vertical slice now?** Identify any clear 4.7 rule that blocks or changes locally generated Phaser games in a sandboxed web view.
2. **Would today's architecture create regret later?** Identify choices that would make future App Store distribution or public sharing need a rewrite, especially native API exposure, downloaded code/content, manifests, moderation/catalog requirements, payments, and privacy.

The output is a short go/change/stop note with explicit unknowns and reversible precautions. Ambiguity may remain for a later public-release review; M0 does not promise legal or App Review certainty.

## Tests

- Sandbox escape attempts, disallowed URLs, bridge fuzzing, console capture, blank render, heartbeat loss, input probe, restart, and content-process termination.
- Lean 4.7 note reviewed against the current official guideline page and checked for an immediate blocker or architectural regret.

## Acceptance

- WebKit can enforce and observe the universal v1 runtime floor on representative target devices, or the architecture is revised before proceeding.
- Guideline 4.7 has a concise build-now and regret-later decision, with unknowns deferred honestly to the public-release milestone.
- Required CI is green on `main`.
