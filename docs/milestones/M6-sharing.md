# Milestone 6: Static Sharing

## Outcome

Publish an explicitly selected passing revision as static files, without coupling authoring or play to the host.

## Deliverables

- Versioned static bundle builder and deterministic manifest.
- Thin host API: create deployment, upload immutable files, query status, obtain public URL, unpublish.
- Publish preview naming project, revision, included files, destination, and public visibility.
- Share sheet and deployment history stored locally.
- Host-side content-type/size limits, abuse controls, deletion path, and basic operational runbook.
- Configuration supports the owner's host but does not hard-code the Oracle VM as a runtime dependency.

## Tests

- Static bundle plays on a generic static test server with no Playloom API.
- Golden bundle is byte-deterministic for identical input.
- Secret/privacy canaries never enter an upload.
- Upload resume/retry is idempotent; wrong deployment cannot be unpublished.
- Authoring, local play, export, and import work while the host is unreachable.
- End-to-end publish/load/unpublish runs in an isolated CI environment.

## Acceptance

- A passing game receives a working URL after explicit confirmation.
- Unpublish removes the deployment from the host and UI states its limits honestly.
- Host outage does not impair any non-sharing workflow.
- Required CI is green on `main`.
