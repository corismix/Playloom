# ADR-002: Stable API-key providers; experimental subscription access

- Status: accepted

## Decision

Stable v1 providers are OpenRouter, OpenAI, and OpenCode Go API keys stored in Keychain. ChatGPT subscription OAuth is an experimental device-direct spike and may be omitted. No remote OpenCode process or model proxy is used.

## Why

The stable product should depend on documented provider APIs rather than a consumer-subscription compatibility surface. Device-direct access keeps Playloom from handling or reselling tokens.

## Consequences

Provider adapters share a contract. Experimental ChatGPT can be disabled without changing projects or stable adapters. No app-owned server sees prompts or provider secrets.
