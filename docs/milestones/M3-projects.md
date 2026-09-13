# Milestone 3: Projects

## Outcome

Add dependable local project persistence, revisions, and portable snapshots.

## Deliverables

- Expand Milestone 2's durable run journal and minimal passing-revision transaction into the app-private multi-project store, the canonical source of truth.
- Phone-first game-card library with create, search, rename, duplicate, delete, and reopen; each project owns its chat, current passing revision, run history, and project settings.
- iPhone navigates Library → Project and switches between Chat and Play; iPad may show project navigation, chat, and play with `NavigationSplitView`.
- Full immutable passing-revision and conversation history, candidate journal, computed compare summary, and rollback. Restore writes a new revision derived from the selected older snapshot.
- Versioned `playloom.json`, asset manifest, and assertion schema.
- Files import copies and validates a project into app storage.
- Files export writes a source snapshot or privacy-filtered playable snapshot; Playloom never edits an external folder in place.
- Migration framework and storage-recovery UI.
- Global settings for provider accounts/keys, default model, privacy/storage, accessibility, diagnostics, and licenses; project settings for name, provider override, export, revision storage, and delete/duplicate.
- Screenshot/annotation feedback records whether it captures only the game or surrounding UI and requires explicit disclosure before an image is sent to a provider.

## Tests

- Create/edit/terminate/reopen and revision rollback, including base-revision mismatch, restore-as-new-revision, and project/chat/run/current-pointer consistency.
- Low disk, interrupted atomic write, external import mutation, duplicate identifiers, and corrupt manifest.
- Import/export-delete-reimport round trip.
- Export canaries prove keys, tokens, private logs, and device paths are absent.
- Every prior format fixture migrates or fails with a useful non-destructive error.

## Acceptance

- App-private state remains correct if the originally imported/exported Files item changes or disappears.
- A passing exported game re-imports and plays unchanged.
- Revisions survive app termination and rollback is deterministic.
- Required CI is green on `main`.
