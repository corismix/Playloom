# Milestone 5: Authoring Experience and Portability

## Outcome

Make the core loop dependable for daily personal use without publishing.

## Deliverables

- Project library, rename/duplicate/delete, starter selection, and recent revision state.
- Chat refinements, revision comparison summary, rollback, and per-asset regenerate/import.
- Files app import/export and source-vs-share export privacy preview.
- Provider settings, model choice, connection health, per-generation limits, and clear provider-charge language.
- iPad layouts, keyboard support, orientation handling, accessibility pass, and reduced-motion shell.
- Diagnostics bundle the user explicitly exports.

## Tests

- Data migration from every prior project format fixture.
- Interrupted generation, low storage, background/foreground, memory pressure, offline launch, and provider timeout.
- VoiceOver and Dynamic Type UI checks for critical flows.
- Export canary suite proves credentials, private chat, logs, and device paths are excluded.
- Full create-generate-play-refine-rollback-export-import UI journey.

## Acceptance

- The internal prompt suite meets the documented quality target or the target and failures are reviewed before scope proceeds.
- Exported source re-imports and runs unchanged.
- The complete authoring flow works without a Playloom account or app backend.
- Required CI is green on `main`.
