# Milestone 2: Reliability

## Outcome

Make generation failure bounded, diagnosable, and reversible.

## Deliverables

- Typed patch allowlist with path, type, size, origin, and secret-like-content validation.
- Candidate staging and atomic promotion of the last passing state.
- Universal floor as an app-owned fixed suite.
- Constrained game-plan schema and game-specific checks generated from it.
- Structured run report separating universal failures from plan-specific failures.
- Failure-classified recovery per ADR-008: sanitized diagnostic repair only for malformed JSON, syntax, or actionable crashes; blind resampling for logic/behavior failures.
- Visible recovery budget capped at two rounds after the initial candidate.
- Privacy-safe per-provider/model telemetry records failure class, strategy, round, and whether the next candidate passed.
- Rollback after failed checks or exhausted repair.
- Cancellation and interrupted-run recovery.

## Tests

- Traversal, absolute path, symlink/archive, forbidden type/origin, oversized content, secret canary, partial stream, and malformed patch corpus.
- Universal checks cannot be deleted, weakened, or marked passing by generated plan data.
- Game-specific fixtures cover motion, score/state change, entity appearance, transition, and reset.
- Crash/relaunch at every orchestrator transition is replay-safe.
- Recovery exhaustion restores the prior passing candidate.
- Strategy tests prove behavioral failures do not self-condition on failed code, while diagnosable failures receive only bounded sanitized evidence.
- Telemetry tests prove prompts, source, raw responses, and credentials are never logged.

## Acceptance

- Failed generation or edit cannot corrupt or replace the last passing game.
- Reports clearly identify fixed runtime failures versus plan-specific behavior failures.
- Recovery always stops at the visible two-round bound.
- Run reports distinguish diagnostic repair from blind resampling, and telemetry can compare success by model and failure class.
- Required CI is green on `main`.
