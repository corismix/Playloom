# Milestone 1: Vertical Slice

**Status: complete and device-proven (September 13, 2026).** A fresh OpenCode Go generation passed all seven reported runtime checks on a physical iPhone, produced a playable touch-controlled game, and accepted an edit that visibly changed the score HUD. Required iOS and docs CI passed on `main` at commit `a3f48d723bb678b37d5a8db3b0c247508288248b` ([iOS run](https://github.com/corismix/Playloom/actions/runs/34722525048), [docs run](https://github.com/corismix/Playloom/actions/runs/34722525211)).

## Outcome

Complete one narrow product loop: prompt → one stable provider → Phaser project → universal checks → play → chat edit → patch/reload.

## Deliverables

- One SwiftUI app target organized into `App`, `Projects`, `Providers`, `Runtime`, `Generation`, and `Assets` folders.
- Minimal in-app project workspace sufficient for one current project; broad persistence waits for Milestone 3.
- One stable API-key provider chosen from OpenRouter, OpenAI, or OpenCode Go, behind the provider protocol.
- Keychain-backed key entry/disconnect.
- One vendored Phaser starter and typed full-project/patch response formats.
- Sandboxed game preview and universal checks: load, no fatal JavaScript error, non-blank canvas, live heartbeat, input path, and restart.
- Chat edit that validates a patch, reloads the candidate, reruns checks, and retains the previous passing in-memory/draft state on failure.
- Procedural placeholder shapes only; no image-generation dependency.

## Tests

- Fake provider covers generation, stream failure, malformed response, cancellation, and patch edit.
- Golden Phaser output parses and runs.
- Broken fixtures cover load error, console error, blank canvas, heartbeat loss, input failure, and restart failure.
- End-to-end simulator UI test completes prompt → play → edit → patched reload.
- Generated content cannot navigate, access credentials, or write outside its candidate workspace.

## Acceptance

- One prompt becomes a playable Phaser game through the selected stable provider.
- A chat edit changes the game and successfully reloads it.
- Every accepted candidate passes the universal floor.
- No Plain Canvas, vision, public sharing, Image Playground, or ChatGPT dependency enters the slice.
- Required CI is green on `main`.
