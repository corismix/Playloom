# Security and Privacy Model

## Goals

- A generated game cannot reach model credentials or privileged native APIs.
- Credentials do not leave the device except in requests to the provider they authorize.
- A project can be exported or published without private chat, secrets, logs, or unrelated files.
- A malicious model response, imported project, or generated script cannot escape the project boundary.

## Credentials

API keys, access tokens, refresh tokens, account identifiers that require protection, and PKCE transaction state live in iOS Keychain items with the narrowest practical accessibility class. Secrets are never stored in `UserDefaults`, project files, logs, crash metadata, screenshots, clipboard history, or publish bundles.

Provider code asks a credential object to authorize a request. It does not expose raw persistent secrets to feature modules. Disconnect deletes the provider's Keychain items and clears cached authorization state. Refresh is serialized to avoid token reuse races.

ChatGPT subscription login uses `ASWebAuthenticationSession`, Authorization Code + PKCE, state verification, an exact callback scheme, and device-side token exchange. No embedded password form and no Playloom relay server are permitted. The implementation must be rechecked against the current open-source Codex client and provider behavior at every release because the third-party compatibility surface may change.

## Web runtime

Generated content is untrusted:

- use a dedicated, ephemeral web view for evaluation;
- keep the native bridge small, typed, and versioned;
- deny navigation, popups, downloads, clipboard, sensors, camera, microphone, location, and arbitrary file access;
- inject a strict CSP and block undeclared outbound requests at the navigation/resource layer;
- vendor runtime libraries rather than rely on mutable CDN content;
- do not expose app cookies, provider headers, credentials, or other project paths;
- terminate and rebuild the web view after a failed or timed-out run.

Imported projects go through the same checks as generated projects.

## Model and prompt handling

Only the selected project's required files, user instruction, and sanitized run report go to the selected model. Screenshots sent for vision review are cropped to the game view and checked for accidental shell overlays. The UI identifies which provider receives text or images before the request.

Model output cannot expand scope, request secrets, change provider settings, enable publishing, or approve its own code. Repair packets redact credentials, authorization headers, device paths, user identifiers, and unrelated chat.

## Export and publish

An allowlist constructs exports from the manifest. Before release, tests seed projects with canary secrets and prove none survive export or publish. Publishing always shows destination, project, revision, and visibility. Unpublish removes the public deployment when supported, while making no claim that third-party caches or prior downloads are erased.

## Supply chain

Dependencies are pinned and recorded. CI runs secret scanning, license checks, tests, and a release archive inspection. Runtime templates record Phaser and template versions. Updating a template cannot silently rewrite existing projects.

## Abuse and content

v1 has no public feed and no server-side user account. The app still needs local warnings and provider-policy handling for disallowed image or text generation. A static host needs file-size/type limits, rate controls independent of the app, abuse reporting, and a takedown path before public sharing ships.

## Release blockers

- Secret appears in logs, exported ZIP, screenshot packet, or publish bundle.
- Generated content can invoke an undeclared native method or outbound origin.
- OAuth state/PKCE or callback validation is bypassable.
- Provider tokens transit an app-owned server.
- A generated/imported project can read another project.
- A failed candidate can replace the last passing revision.
