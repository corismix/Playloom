# ADR-004: Universal floor plus game-specific checks

- Status: accepted

## Decision

Every candidate passes a fixed universal floor: loads, has no fatal JavaScript error, renders non-blank content, keeps a heartbeat, accepts input, and restarts. Separately, constrained assertions derived from the game plan test game-specific behavior such as movement or score changes.

## Why

Universal failures are objective and must never depend on generated expectations. Game mechanics vary and need explicit plan-derived observations.

## Consequences

Project/model data cannot disable the universal suite. The vertical slice ships the universal floor. Reliability adds richer game-specific checks and bounded repair. Vision review is postponed and cannot later waive either required layer.
