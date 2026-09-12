# ADR-005: One target before packages

- Status: accepted

## Decision

Start with one app target and organize code into App, Projects, Providers, Runtime, Generation, and Assets folders with clean protocols.

## Why

The initial vertical slice does not justify package/target build overhead. Source boundaries can be tested without freezing package APIs too early.

## Consequences

A later split needs a measured benefit such as reuse, isolation, build time, or ownership. Folder boundaries must still prevent credentials leaking into runtime code.
