# Milestone 4: Assets

## Outcome

Move from procedural prototypes to controlled, replaceable assets without making paid or device-specific generation mandatory.

## Deliverables

- Stable asset manifest/logical IDs and single-asset replacement.
- Procedural Phaser geometry/simple safe SVG baseline.
- User image import with decode, normalization, size/dimension, metadata, provenance, and transparency handling.
- Optional remote image-provider seam, selected separately from text.
- Experimental Image Playground adapter behind capability/availability checks.
- Placeholder fallback whenever generation is absent, cancelled, or fails.

## Tests

- Malformed images, decode bombs, oversized dimensions, metadata stripping, orientation, transparency, duplicate IDs, and rollback.
- Unsupported Image Playground device/OS/region and cancellation do not block a project.
- Remote image fixture proves text credentials are not accidentally reused.
- Export carries correct asset notices/provenance and no private generation state.

## Acceptance

- A game remains completable with procedural assets and user imports only.
- One asset can change without rebuilding unrelated code.
- Image Playground remains optional and experimental.
- Required CI is green on `main`.
