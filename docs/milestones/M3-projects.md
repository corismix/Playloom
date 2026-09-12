# Milestone 3: Projects

## Outcome

Add dependable local project persistence, revisions, and portable snapshots.

## Deliverables

- App-private project store as the canonical source of truth.
- Library actions: create, rename, duplicate, delete, reopen.
- Immutable passing revisions, candidate journal, compare summary, and rollback.
- Versioned `playloom.json`, asset manifest, and assertion schema.
- Files import copies and validates a project into app storage.
- Files export writes a source snapshot or privacy-filtered playable snapshot; Playloom never edits an external folder in place.
- Migration framework and storage-recovery UI.

## Tests

- Create/edit/terminate/reopen and revision rollback.
- Low disk, interrupted atomic write, external import mutation, duplicate identifiers, and corrupt manifest.
- Import/export-delete-reimport round trip.
- Export canaries prove keys, tokens, private logs, and device paths are absent.
- Every prior format fixture migrates or fails with a useful non-destructive error.

## Acceptance

- App-private state remains correct if the originally imported/exported Files item changes or disappears.
- A passing exported game re-imports and plays unchanged.
- Revisions survive app termination and rollback is deterministic.
- Required CI is green on `main`.
