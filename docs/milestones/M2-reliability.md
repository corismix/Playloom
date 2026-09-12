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
- Honest long-generation progress UI: named stages at minimum, plus streamed partial progress when the active provider supports it.
- Foreground/background lifecycle handling: warn users to keep the app open when a request cannot continue under suspension, detect an interrupted request, and recover without corrupting or losing the last passing project.
- Keep the screen awake while foreground generation is active, then always restore the normal idle-timer behavior when generation finishes, fails, or is cancelled.

## Tests

- Traversal, absolute path, symlink/archive, forbidden type/origin, oversized content, secret canary, partial stream, and malformed patch corpus.
- Universal checks cannot be deleted, weakened, or marked passing by generated plan data.
- Game-specific fixtures cover motion, score/state change, entity appearance, transition, and reset.
- Crash/relaunch at every orchestrator transition is replay-safe.
- Recovery exhaustion restores the prior passing candidate.
- Strategy tests prove behavioral failures do not self-condition on failed code, while diagnosable failures receive only bounded sanitized evidence.
- Telemetry tests prove prompts, source, raw responses, and credentials are never logged.
- Lifecycle tests cover lock/background suspension, foreground return, interrupted provider requests, retry/recovery, and idle-timer cleanup on success, failure, and cancellation.
- Progress tests cover every named stage and provider streaming/non-streaming behavior without inventing completion percentages.

## Acceptance

- Failed generation or edit cannot corrupt or replace the last passing game.
- Reports clearly identify fixed runtime failures versus plan-specific behavior failures.
- Recovery always stops at the visible two-round bound.
- Run reports distinguish diagnostic repair from blind resampling, and telemetry can compare success by model and failure class.
- Multi-minute generation never presents a silent/static wait: users see the current stage and an explicit keep-open warning whenever background continuation is unavailable.
- Suspending or locking during generation cannot replace the last passing game or leave the app permanently busy; return to foreground gives a clear recovery path.
- Required CI is green on `main`.
