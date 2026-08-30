# Architecture Decision Records

An ADR captures one architecturally significant decision: the context it was
made in, the decision itself, and the consequences that follow from it. The
records are immutable history — when a decision changes, add a new ADR and mark
the old one as superseded instead of rewriting it.

## Index

| ADR | Title | Status |
| --- | --- | --- |
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted |
| [0002](0002-strict-linting-and-warning-free-builds.md) | Strict linting and warning-free builds in CI | Accepted |
| [0003](0003-track-requirements-in-the-repository.md) | Track requirements in the repository, linked to tests by identifier | Accepted |
| [0004](0004-dutch-first-localised-from-the-start.md) | Dutch first, localised from the start | Accepted |

## How to add one

1. Copy [`template.md`](template.md) to `docs/adr/NNNN-short-title.md`, using
   the next free four-digit number.
2. Fill in the sections. Keep it short — one page is usually enough.
3. Add a row to the index above.
4. Link the ADR from the pull request that implements the decision.

## When to write one

Write an ADR when the decision is expensive to reverse or when a future reader
would otherwise wonder "why is it done this way?". For example:

- Choosing or dropping a dependency, framework or Apple API (SwiftData,
  Observation, an HTTP client).
- The app's module and layer boundaries, or how state flows through the app.
- Data persistence, migration and caching strategies.
- Networking, authentication or error handling approaches.
- Testing strategy and what "done" means for a feature.
- Anything that relaxes a project rule, such as an approved lint exception or a
  suppressed compiler warning.

Renaming a variable, fixing a bug, or adding a view that follows the existing
patterns does not need an ADR.
