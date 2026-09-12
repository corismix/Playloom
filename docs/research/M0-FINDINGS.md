# M0 Findings

Date: 2026-09-12
Status: implementation spike prepared; simulator/device verification remains part of the M0 gate.

## Build now

Proceed with the local-only vertical slice. The architecture uses a native SwiftUI shell and a project-scoped `WKWebView` with local content, no generated native code, a narrow message bridge, blocked navigation/network by default, and no accounts or commerce. The spike implements instrumentation for load, fatal JavaScript errors, non-blank canvas pixels, frame heartbeat, synthetic input, restart, and web-content-process termination.

## Architectural regret check

Current App Store Review Guideline 4.7 explicitly addresses HTML5 mini apps/mini games. The local authoring slice does not need public catalog or hosting features now, but later distribution could require review metadata, indexing, age/content handling, privacy controls, limits on exposed native APIs, reporting/moderation, and compliance with any current 4.7 subclauses. Avoid regret by keeping a versioned project manifest, a tiny audited bridge, no arbitrary native API access, no in-game commerce, provenance/licensing metadata, and sharing isolated behind a later milestone. Recheck the current rule before TestFlight/App Store/public sharing.

This is a lean product/architecture assessment, not legal certainty or a prediction of App Review.

Official source reviewed: https://developer.apple.com/app-store/review/guidelines/#mini-apps-mini-games-streaming-games-chatbots-plug-ins-and-game-emulators

## Verification plan

Required CI compiles the app and unit tests on a pinned macOS runner. Simulator integration must prove all six checks against the bundled fixture plus failure fixtures. A physical iPhone/iPad pass should confirm touch input, WebGL/canvas rendering, process recovery, orientation, and energy behavior before M0 is finally closed.

## OpenCode Go client identity note

OpenCode Go's current "Where can I use it?" contract allows OpenCode and other coding agents producing similar traffic. A client must identify itself with its own user agent and send a stable `x-opencode-session` value for each conversation. Playloom maps that value to one generated opaque identifier retained by the provider instance for the project conversation; it sends no account identity in the header.

Source reviewed: https://opencode.ai/docs/go/#where-can-i-use-it
