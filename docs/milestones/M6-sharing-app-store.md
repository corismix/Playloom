# Milestone 6: Sharing and App Store

## Outcome

Only after the local product is reliable, decide and implement the public-distribution shape permitted by current platform rules.

## Deliverables

- Revalidate App Store Guideline 4.7 findings from Milestone 0 against current text and the implemented architecture, including filtering/reporting/blocking, per-software consent, indexing/universal links, age handling, and limits on exposed native APIs where the current rule applies.
- Implement any required indexing, metadata, content controls, moderation/reporting, review access, age handling, or native API restrictions before public sharing.
- MIT-licensed runtime/export templates with per-template license files and third-party notice inventory.
- Deterministic static bundle that excludes chat, runs, revisions, credentials, provider metadata, and device paths.
- If approved by the distribution decision: thin host API for immutable upload/status/URL/unpublish and explicit publish preview.
- Privacy manifest/labels, support/privacy pages, export compliance, licenses, security review, and App Store review brief.
- Recheck the BYOK release posture: provider-specific disclosure, billing responsibility, key extraction risk on a client device, restricted-key/quota guidance where available, and revoke/replace support. Any future user-owned relay/self-hosted endpoint is a separate trust model with TLS, authentication, local-network permission, and capability discovery.
- Release evidence for generated-content resource-network enforcement, WebContent process recovery, memory/CPU limits, viewport/orientation, audio/haptics, storage, and screenshot/diagnostic privacy.
- Vision-based screenshot evaluation remains a separate optional post-v1 experiment; it is not smuggled into this gate.

## Tests

- Generic static server runs the exported bundle without a Playloom API.
- License/notice fixture proves no GPL/AGPL or accidental Playloom app source enters exports.
- Privacy/secret canary and deterministic bundle checks.
- Host outage cannot impair creation, local play, projects, or export.
- Physical-device and release-archive checks required by the final 4.7 architecture decision.

## Acceptance

- Current Guideline 4.7 classification and every relevant requirement have evidence and an owner.
- Public sharing ships only if that review says the architecture is acceptable; otherwise export remains local/manual.
- Release candidate is free, needs no Playloom account/backend, and does not resell tokens.
- Required CI and tagged release workflow are green.
