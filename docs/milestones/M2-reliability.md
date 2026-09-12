# Milestone 2: Reliability

## Outcome

Make generation failure bounded, diagnosable, and reversible.

## Deliverables

- Typed patch allowlist with path, type, size, origin, and secret-like-content validation.
- Candidate staging and atomic promotion of the last passing state.
- Universal floor as an app-owned fixed suite.
- Constrained game-plan schema and game-specific checks generated from it.
- Structured run report separating universal failures from plan-specific failures.
- Sanitized repair packet and visible fixed repair budget, default two attempts.
- Rollback after failed checks or exhausted repair.
- Cancellation and interrupted-run recovery.

## Tests

- Traversal, absolute path, symlink/archive, forbidden type/origin, oversized content, secret canary, partial stream, and malformed patch corpus.
- Universal checks cannot be deleted, weakened, or marked passing by generated plan data.
- Game-specific fixtures cover motion, score/state change, entity appearance, transition, and reset.
- Crash/relaunch at every orchestrator transition is replay-safe.
- Repair exhaustion restores the prior passing candidate.

## Acceptance

- Failed generation or edit cannot corrupt or replace the last passing game.
- Reports clearly identify fixed runtime failures versus plan-specific behavior failures.
- Repair always stops at the visible bound.
- Required CI is green on `main`.
