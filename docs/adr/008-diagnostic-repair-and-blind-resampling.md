# ADR-008: Diagnostic repair and blind resampling

- Status: accepted

## Decision

Generation recovery uses two strategies selected by the failure class:

- Send the failed candidate plus a sanitized diagnostic repair packet only for diagnosable structural failures: malformed provider JSON, syntax errors, or a captured runtime crash with actionable evidence.
- Blindly resample from the original request for logic and behavioral failures, without feeding the failed candidate back to the model.

Recovery is capped at two rounds after the initial candidate. The bound is visible in the run report. Every attempt logs provider, model, failure class, strategy, round, and whether that strategy produced the next passing candidate. Logs exclude prompts, source, credentials, and raw provider bodies.

## Why

Iterative code repair research finds most gains in the first two feedback rounds and larger gains from more capable models. A fixed two-round cap captures the useful part of that curve while keeping latency and spend bounded. See [arXiv:2604.10508](https://arxiv.org/abs/2604.10508).

For weaker code models, self-conditioning on a failed candidate can anchor the next answer to the same mistakes. Blind resampling outperforms self-repair in that setting. Logic and behavioral failures often lack a precise causal diagnostic, so showing the old candidate adds anchoring risk without useful feedback. See [arXiv:2607.26117](https://arxiv.org/abs/2607.26117).

## Consequences

The orchestrator classifies failures before retrying. Unknown or mixed failures default to blind resampling. A malformed response extractor may make one focused formatting repair because its failure is structural and diagnosable. Runtime repair packets contain only bounded, sanitized evidence.

Per-model telemetry shows which recovery strategy actually fixes each failure class. Routing policy may change from that evidence, but model size or reputation alone never overrides the two-round cap. Exhaustion restores the last passing candidate.
