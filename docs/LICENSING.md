# Licensing Policy

## Playloom source

Playloom is licensed under the MIT License. The project changed from GPL-3.0 during the specification phase, before implementation code or outside contributions were added. The repository's `LICENSE` file is authoritative.

## Generated and exported games

Playloom must not impose copyleft obligations on a user's game. Bundled runtime starters, export wrappers, generated glue, and other Playloom-authored template files are MIT licensed. A template may instead use CC0-1.0 when it contains only trivial scaffolding and its directory includes an explicit CC0 notice.

Every template directory must carry its own license file and SPDX metadata. Export tooling includes only the notices required by the selected template and third-party dependencies. It never copies Playloom's application source license into a game as if the game were a derivative of the app.

## Third-party code and assets

Phaser and any other dependency retain their own licenses and notices. CI must build a notice inventory for vendored runtime dependencies. User-imported, model-generated, and externally generated assets remain subject to their own provenance and provider terms; Playloom does not relicense them.

## Release gate

Before templates ship, verify their exact contents and notices, export a fixture, and confirm the fixture has no GPL/AGPL dependency or accidental Playloom-source inclusion. This is a technical policy, not a promise about rights the user does not have in imported or generated material.
