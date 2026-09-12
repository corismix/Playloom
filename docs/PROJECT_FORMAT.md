# Portable Game Project Format

## Goals

A project is readable, versioned, deterministic to package, and playable as static web content. It contains no Playloom credential and does not require a Playloom account.

## Proposed v1 layout

```text
MyGame.playloom/
├── playloom.json
├── game/
│   ├── index.html
│   ├── game.js
│   ├── styles.css
│   └── vendor/
│       └── phaser.min.js
├── assets/
│   ├── manifest.json
│   ├── sprites/
│   ├── audio/
│   └── fonts/
├── tests/
│   └── assertions.json
├── revisions/
│   └── index.json
└── .playloom/
    ├── chat.jsonl
    └── runs/
```

The export profile may omit `.playloom`, revision bodies, chat, and run evidence. A source archive can include them after a separate privacy preview.

## `playloom.json`

Required fields:

- `formatVersion`
- `projectID` (random, non-account identifier)
- `title`
- `runtime`: `phaser` or `canvas`
- `runtimeVersion`
- `entrypoint`
- `orientation`
- `viewport`
- `controls`
- `assetManifest`
- `assertions`
- `createdAt` and `updatedAt`

Optional fields include description, author alias, accessibility notes, approved network origins, template identity, and engine metadata. Unknown fields are preserved where safe. A major format version is never upgraded in place without a new revision.

## Asset manifest

Each logical asset records its stable ID, path, media type, dimensions/duration, cryptographic digest, source (`imagePlayground`, provider, imported, generatedShape), generation prompt if the user elects to retain it, and license/provenance note. Runtime code refers to logical IDs, allowing one asset to be regenerated without rewriting unrelated source.

## Assertions

`tests/assertions.json` declares observable facts such as boot timeout, ready signal, minimum non-background pixel ratio, entities expected, permitted initial stillness, motion/state deltas, and restart behavior. Assertions are constrained data interpreted by Playloom and a bundled JS harness, not arbitrary native scripts.

## Revision model

A revision is immutable after evaluation. Metadata records parent revision, instruction summary, changed file digests, provider/model aliases, run result, and timestamps. Raw credentials and authorization headers are forbidden. `current` points only to a passing revision; candidate state lives outside the canonical export.

## Static build profile

The share bundle contains only the entrypoint, approved source, normalized assets, vendored runtime, and a small generated metadata file. It excludes chat, run logs, revisions, provider metadata, private prompts, and credential aliases. The build must run from a static origin with no Playloom API.
