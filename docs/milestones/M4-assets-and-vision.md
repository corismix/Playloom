# Milestone 4: Assets and Visual Review

## Outcome

Generate, import, replace, and evaluate game art independently of the text model.

## Deliverables

- Asset manifest workflow and stable logical IDs.
- Image Playground integration behind runtime availability checks.
- Shape/vector placeholder generator as the universal free fallback.
- Separate remote image-provider seam and one adapter using an existing v1 provider capability where supported.
- Image normalization, dimension/size limits, transparency handling, digest and provenance.
- WebView/renderer screenshot capture with WebGL fallback.
- Optional vision evaluation with cropped screenshot and narrow rubric.
- Single-asset regeneration and rollback.

## Tests

- Availability matrix: supported Image Playground, unavailable device/region/OS, cancellation, and failure.
- Image decode bombs, malformed data, wrong dimensions, metadata stripping, and oversized assets.
- Screenshot fixtures for blank, clipped, illegible, placeholder-heavy, and valid scenes.
- Vision adapter fixtures prove it cannot waive the deterministic floor.
- Screenshot packets contain no shell UI, secrets, or other project data.

## Acceptance

- A project can be completed with placeholders and no remote image model.
- On a supported device, Image Playground can create an asset that is normalized and inserted by logical ID.
- With vision disabled or unavailable, all programmatic checks and repair still work.
- Required CI is green on `main`.
