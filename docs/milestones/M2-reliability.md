# Milestone 2: Reliability

## Outcome

Make generation failure bounded, diagnosable, and reversible.

## Delivery sequence

### M2A: durable, watchable work

- Typed plan/check/event model and a durable single-project run journal created before provider work.
- Stable run, candidate, operation, and base-revision IDs; persisted background-task metadata supports OS relaunch reattachment.
- Honest replayable activity UI with Textual-rendered Markdown summaries. App-owned milestones only; never raw chain-of-thought or invented percentages.
- Cancellation and separate foreground, suspension, OS-relaunch/interrupted, and force-quit states.

### M2B: evidence and safe promotion

- Evidence-strengthened universal and game-specific checks, failure classification, and bounded repair/resampling.
- App-private candidate snapshots plus minimal immutable passing revisions.
- Transactional promotion of candidate, report, revision, and current pointer; base-revision mismatch blocks stale completion.
- Restore creates a new revision; full multi-project history and library remain Milestone 3.

## Deliverables

- Typed patch allowlist with path, type, size, origin, and secret-like-content validation.
- Candidate staging and atomic promotion of the last passing state, pinned to the expected base revision.
- Universal floor as an app-owned fixed suite.
- One-response constrained game-plan schema derived separately from the verbatim prompt: core loop, actions, controls, entities, win/lose conditions, and done-when checks.
- Evidence-per-mechanic mapping: state delta, screenshot, or input trace/decisive frames; reject unused runtime-state fields and mark claims without evidence unverified.
- Game-specific checks generated from the typed plan.
- Pre-recovery failure classification: model output, game runtime, validator/harness, or platform/lifecycle; never repair generated code for a harness/platform fault or weaken an assertion to pass.
- Structured run report separating the WebKit bridge prerequisite, six universal runtime checks, and plan-specific failures. Universal success is labeled “Basic runtime passed.”
- Fresh-event boundaries or operation tokens for input and restart; heartbeat requires increasing frame values, and fatal errors are checked through the end of active probes.
- Failure-classified recovery per ADR-008: sanitized diagnostic repair only for malformed JSON, syntax, or actionable crashes; blind resampling for logic/behavior failures. UI says “Trying another version” for resampling and reserves “Fixing…” for evidence-backed repair.
- Visible recovery budget capped at two rounds after the initial candidate.
- Privacy-safe per-provider/model telemetry records failure class, strategy, round, and whether the next candidate passed.
- Rollback after failed checks or exhausted repair.
- Cancellation and interrupted-run recovery backed by a durable journal. Background URL-session task IDs, request-body/response locations, and run metadata survive relaunch; continuations and response bytes cannot exist only in memory.
- Honest long-generation progress UI: collapsed consumer summaries and expandable recorded detail, plus streamed partial progress when the active provider supports it. Textual is the pinned Markdown renderer; raw provider reasoning is neither shown nor persisted.
- Foreground/background lifecycle handling: describe lock/suspension as best effort, reattach eligible background transfers after OS relaunch, mark unrecoverable/force-quit work interrupted, and resume validation only in foreground without corrupting the last passing project.
- Provider setup discloses BYOK data flow and billing, supports key test/replace/revoke and rate-limit/expired-key states, and reports usage as unavailable when the provider omits it.
- Enforce resource-level network policy for generated WebKit content and define WebContent process recovery, memory/CPU failure, orientation/viewport, audio, storage, and screenshot-diagnostic boundaries.
- Keep the screen awake while foreground generation is active, then always restore the normal idle-timer behavior when generation finishes, fails, or is cancelled.

## Tests

- Traversal, absolute path, symlink/archive, forbidden type/origin, oversized content, secret canary, partial stream, and malformed patch corpus.
- Universal checks cannot be deleted, weakened, or marked passing by generated plan data; stale input/restart events, duplicate heartbeat frames, and fatal errors triggered during probes fail.
- Game-specific fixtures cover motion, score/state change, entity appearance, transition, and reset.
- Crash/relaunch at every orchestrator transition is replay-safe, including background completion delivered into a new process and a stale completion after restore/newer edit.
- Recovery exhaustion restores the prior passing candidate.
- Strategy tests prove behavioral failures do not self-condition on failed code, while diagnosable failures receive only bounded sanitized evidence.
- Telemetry tests prove prompts, source, raw responses, and credentials are never logged.
- Lifecycle tests cover lock/background suspension, foreground return, interrupted provider requests, retry/recovery, and idle-timer cleanup on success, failure, and cancellation.
- Progress tests cover every named stage and provider streaming/non-streaming behavior without inventing completion percentages or displaying chain-of-thought.

## Acceptance

- Failed generation or edit cannot corrupt or replace the last passing game.
- Reports clearly identify fixed runtime failures versus plan-specific behavior failures.
- Recovery always stops at the visible two-round bound.
- Run reports distinguish diagnostic repair from blind resampling, and telemetry can compare success by model and failure class.
- Multi-minute generation never presents a silent/static wait: users see the current stage and an explicit keep-open warning whenever background continuation is unavailable.
- Suspending or locking during generation cannot replace the last passing game or leave the app permanently busy; return to foreground gives a clear recovery path.
- Required CI is green on `main`.
