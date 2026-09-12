# ADR-003: Generated patches, never generated native code

- Status: accepted

## Decision

Models may generate constrained web project files and declarative data. Playloom never compiles or runs generated Swift or dynamically loaded native code.

## Why

A web sandbox and typed patch boundary are easier to inspect, roll back, export, and keep within platform policy than model-produced native executables.

## Consequences

Native performance is not a v1 goal. A future SpriteKit runtime interprets versioned `game.json` data and keeps the same no-generated-Swift rule.
