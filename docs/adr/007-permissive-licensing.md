# ADR-007: Permissive app and template licensing

- Status: accepted

## Decision

License Playloom under MIT. License Playloom-authored runtime/export templates under MIT or explicit CC0.

## Why

A user's exported game should not acquire a copyleft obligation merely by using Playloom scaffolding.

## Consequences

Third-party licenses and asset/provider terms still apply. Template directories carry their own notices, and CI inspects export fixtures for accidental copyleft dependencies or app source.
