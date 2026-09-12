# ADR-006: App-private storage is canonical

- Status: accepted

## Decision

Playloom owns live projects in its app-private container. Files is used only to import a validated copy or export an immutable snapshot.

## Why

This gives atomic writes, revisions, rollback, and isolation without external mutation or security-scoped URL coordination.

## Consequences

Exported folders are not live-linked. Re-import makes a new local copy. UI must explain snapshots clearly.
