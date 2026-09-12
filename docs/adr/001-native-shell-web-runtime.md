# ADR-001: Native shell with a Phaser runtime

- Status: accepted

## Decision

Use SwiftUI for the iPhone/iPad shell and run generated Phaser HTML/JavaScript projects in a sandboxed local `WKWebView`. Plain Canvas is outside v1.

## Why

One runtime narrows templates, validation, instrumentation, and debugging enough to prove the complete loop. Web projects remain inspectable and portable without compiling model-produced native code.

## Consequences

The WebKit bridge/sandbox and App Store Guideline 4.7 are Milestone 0 risks. Phaser is pinned and vendored. A later SpriteKit interpreter may consume declarative `game.json`; it never compiles generated Swift.
