# Portable Game Project Format

## Storage rule

Playloom's app-private container is canonical in v1. Files is a transport boundary only:

- import copies and validates a project into app storage;
- export writes an immutable snapshot;
- Playloom never treats a Files folder as live state or edits it in place.

This keeps atomic revisions and rollback under app control while retaining portability.

## Proposed layout

```text
MyGame.playloom/
├── playloom.json
├── game/
│   ├── index.html
│   ├── game.js
│   ├── styles.css
│   └── vendor/phaser.min.js
├── assets/
│   ├── manifest.json
│   └── images/
├── tests/
│   ├── universal-version.json
│   └── game-assertions.json
└── export-notices/
    ├── TEMPLATE-LICENSE
    └── THIRD-PARTY-NOTICES
```

Chat, run reports, candidate journals, full revision bodies, provider aliases, and other private authoring state remain in app storage and are excluded by default.

## `playloom.json`

Required fields:

- `formatVersion`
- `projectID` (random local identifier)
- `title`
- `runtime` (`phaser` in v1)
- `runtimeVersion`
- `entrypoint`
- `orientation` and `viewport`
- `controls`
- `assetManifest`
- `gameAssertions`
- `createdAt` and `updatedAt`

Unknown safe fields are preserved. A major format change creates a migrated revision rather than rewriting the only copy.

## Runtime checks

Universal checks are defined by the app/runtime version and cannot be disabled by project data: load, no JavaScript crash, non-blank canvas, heartbeat, input, and restart.

`tests/game-assertions.json` contains constrained, game-specific observations derived from the game plan, such as movement, score/state change, entity presence, or transitions. It is data interpreted by the test harness, not native code and not authority to weaken universal checks.

## Revisions

Canonical app storage records immutable revisions with parent, changed digests, instruction summary, check results, and timestamps. The current pointer names only a passing revision. Candidate state is staged separately. Exports are snapshots, not revision peers.

## Assets and licenses

Assets use stable IDs, paths, media types, dimensions, digests, origins, and provenance notes. Playloom-authored runtime/export templates are MIT or explicitly CC0 licensed. Phaser and other dependencies retain their own notices. User/imported/generated assets are not relicensed by Playloom.

## Export profiles

- **Source snapshot:** portable game source, normalized assets, tests, template license, and third-party notices.
- **Playable snapshot:** only files needed to run plus required notices.

Neither profile includes credentials, OAuth tokens, private chat, run logs, candidate journals, device paths, or app-only provider metadata. Public-host packaging is postponed to the final sharing/App Store milestone.
