# Milestone 2: Portable Project Runtime

## Outcome

Create, import, validate, run, export, and re-import a hand-written portable game project.

## Deliverables

- Versioned `playloom.json` and asset/assertion schemas.
- Atomic ProjectStore and immutable revision metadata.
- Bundled Phaser and plain-Canvas starter projects.
- Sandboxed local `WKWebView` runtime with strict CSP, denied navigation, small typed bridge, heartbeat, console collection, and restart.
- Programmatic checks for readiness, errors, blank canvas, entity/state declarations, motion/state change, and restart.
- Runtime report UI and raw diagnostic export with redaction.

## Tests

- Schema and path traversal corpus, including symlink and archive attacks.
- Known-good Phaser/Canvas fixtures pass.
- Broken fixtures cover parse error, console error, blank render, missing ready, no motion, runaway reload, disallowed URL, and failed restart.
- UI tests on iPhone and iPad simulators.
- Export-delete-import round trip preserves the game and excludes local-only data.
- Attempted bridge calls and navigation outside the allowlist fail closed.

## Acceptance

- A hand-written fixture plays offline on iPhone and iPad.
- All deliberately broken fixtures fail for the expected reason.
- Last passing revision survives a failed candidate and app termination.
- Required CI is green on `main`.
