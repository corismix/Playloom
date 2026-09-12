# ADR-001: Native shell with a web game runtime

- Status: accepted

## Decision

Use SwiftUI for the iPhone/iPad product shell and run generated games as local HTML/JavaScript in a sandboxed `WKWebView`, using Phaser or plain Canvas.

## Why

Web projects are fast to generate, easy to inspect, and portable outside Playloom. A native shell gives first-class project, credential, sharing, and device UI without compiling model-produced native code.

## Consequences

The web/native bridge and sandbox are security-critical. Touch input, lifecycle, audio, snapshots, WebGL behavior, and App Store review need explicit tests. A future SpriteKit interpreter consumes declarative `game.json`; it never compiles generated Swift.
