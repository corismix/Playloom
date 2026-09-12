# ADR-004: Programmatic evaluation before vision

- Status: accepted

## Decision

Every candidate must pass deterministic runtime checks. Vision review is an optional additional critic, not the only test and not a prerequisite for a usable app.

## Why

Console failures, blank canvases, stalled loops, and missing motion have objective signals. Deterministic checks are cheaper, repeatable, and available without a vision model.

## Consequences

Templates must expose a small assertion harness. Vision feedback may request repairs but cannot waive a failed programmatic check. Repair attempts are bounded and preserve the last passing revision.
