# ADR-002: Device-direct bring-your-own access

- Status: accepted

## Decision

Support ChatGPT subscription OAuth and API-key providers directly from the device. v1 adapters are ChatGPT subscription, OpenAI, OpenRouter, and OpenCode Go. Store secrets in Keychain. Do not run a remote OpenCode process or model proxy.

## Why

This keeps credentials under user control, avoids an app account/backend dependency, and ensures Playloom never resells tokens.

## Consequences

Provider compatibility lives in the app and needs frequent contract tests. ChatGPT subscription support has higher compatibility risk and must pass dedicated feasibility and release gates. No app-owned server sees prompts or provider secrets.
