# Milestone 7: Public-Release Hardening

## Outcome

Reach a free TestFlight/App Store candidate with measured reliability, reviewed platform compatibility, and no hidden service dependency.

## Deliverables

- Re-run ChatGPT subscription compatibility against the current Codex client and document observed endpoints/flows without committing secrets.
- App Store review brief covering generated web content, external provider access, user-generated content, and static sharing.
- Privacy manifest/labels, support and privacy pages, licenses, export-compliance review, and deletion/unpublish instructions.
- Threat-model review and independent penetration test of project import, web bridge, export, and publish boundaries.
- Performance, energy, storage, crash recovery, and device/OS matrix.
- Release telemetry decision; default remains no third-party analytics.
- Signed archive and reproducible release checklist.

## Tests

- Required unit, integration, UI, migration, security, privacy-canary, and archive-inspection suites.
- Physical-device runs for Image Playground availability, OAuth callback, WebGL snapshot, memory pressure, and backgrounding.
- Live provider smoke lane with explicit owner-controlled credentials.
- 20-prompt benchmark meets or deliberately revises the success target with recorded rationale.
- Chaos check proves Oracle/static-host loss leaves creation, local play, and export working.

## Acceptance

- No release blocker in `SECURITY.md` remains.
- All v1 access paths are current, labeled honestly, and disconnect cleanly.
- App review and provider-policy risks have an owner and fallback, not an assumption.
- Release candidate is free, has no Playloom account/billing requirement, and does not resell tokens.
- Required CI is green on `main`, followed by a green tagged release workflow.
