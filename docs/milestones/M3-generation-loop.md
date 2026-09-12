# Milestone 3: Prompt to Playable

## Outcome

Turn a prompt into a playable web game through a typed, bounded generation and repair loop.

## Deliverables

- Project chat and provider/model selection.
- Prompt/context builder using manifest summaries and only relevant project files.
- Versioned typed patch response protocol with plain-JSON fallback where provider structured output is unavailable.
- Patch validation, staging, deterministic preflight, runtime evaluation, promotion, and rollback.
- Structured repair packet and a default two-attempt repair budget.
- Progress, cancellation, error recovery, and local cost/usage display.
- Golden prompt set spanning arcade, puzzle, platform, and toy interactions.

## Tests

- Fake provider drives each state transition, cancellation point, malformed patch, partial stream, retry, repair exhaustion, and recovery after app restart.
- Golden fixture outputs prove generated template syntax and paths.
- At least 20 prompt scenarios run against deterministic recorded model outputs in required CI.
- Opt-in live evaluation reports first-pass and within-budget pass rates without making the live lane a merge dependency.
- No model output can alter credentials, publish a project, or write outside its candidate revision.

## Acceptance

- A prompt produces a playable passing revision from both bundled runtime templates.
- Failed generation never replaces the last passing build.
- The user sees the bounded repair state and remaining attempt count.
- Required CI is green on `main`.
