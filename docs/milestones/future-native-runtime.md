# Future Milestone: Declarative Native Runtime

## Goal

Explore a versioned `game.json` that can be interpreted by SpriteKit for selected game classes while preserving HTML projects.

## Constraints

- The model emits declarative data and assets, never Swift.
- Schema validation and resource limits precede interpretation.
- Web projects remain supported, exportable, and playable.
- A native conversion is opt-in and creates a new revision.
- This work starts only after v1 release evidence identifies a real benefit in performance, accessibility, or platform integration.

## Exit gate

A representative corpus renders deterministically in a SpriteKit interpreter, invalid data fails closed, and required CI is green. This document does not authorize implementation before that later decision.
