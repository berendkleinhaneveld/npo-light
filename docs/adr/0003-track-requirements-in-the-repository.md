# 0003. Track requirements in the repository, linked to tests by identifier

- **Status:** Accepted
- **Date:** 2026-08-30
- **Deciders:** @berendkleinhaneveld

## Context

NPO light is written by coding agents working one task at a time, under the
repository owner's supervision, test-first. An agent starting a task has no
memory of the conversation in which the app was designed: unless the intent is
written down in the repository, each task re-invents it, and behaviour drifts
in a direction nobody chose.

Two things follow from that. Intent has to live in the repository, next to the
code and in the same pull request diff — not in a chat log, an issue tracker or
someone's head. And it has to be addressable, so that a test can point at the
behaviour it proves and a reader can ask "is this built yet, and what shows
that it works?" without reading the whole suite.

The app is small and the audience is a family, so a heavyweight requirements
process would cost more than it returns. What is needed is the smallest thing
that survives an agent handover.

## Decision

We keep the specification in `docs/requirements/`, one Markdown file per area,
and give every requirement a permanent identifier of the form
`FR-SEARCH-03` (functional) or `NFR-PERF-01` (non-functional).

Each requirement carries a status — `Proposed`, `Accepted`, `Implemented`,
`Deferred` or `Superseded` — and a short list of acceptance criteria written so
that a test can be derived from them. Identifiers are never renumbered and
never recycled; a requirement that changes meaning is superseded by a new one.

A test claims a requirement by naming its identifier in the test's display
name, `@Test("FR-SEARCH-03: typing is not blocked by a slow backend")`, or in a
`// Requirement:` comment where a display name does not fit.

`scripts/requirements-coverage.sh` reads the directory and both test targets
and fails when a test names an identifier that does not exist, when a
requirement marked `Implemented` is named by no test and declares no other
verification, or when the documents themselves are malformed — a duplicate
identifier, a missing or unknown status. It runs as a third CI job, on Linux,
because it needs neither Xcode nor a simulator. A requirement that is
`Accepted` but untested is work not yet done, and does not fail the run.

The workflow for a feature is therefore: pick an `Accepted` requirement, write
the failing test that names it, make it pass, and flip the status to
`Implemented` in the same pull request.

## Alternatives considered

- **GitHub issues as the source of truth** — rejected. Requirements would live
  outside the diff, would not be versioned with the code that implements them,
  and an agent would need network access and a search to find out what it is
  supposed to build.
- **One large `requirements.md`** — rejected. Every pull request touching
  requirements would touch the same file, and the merge conflicts would land
  precisely on the parallel agent work this project depends on.
- **A machine-readable format (YAML, JSON) as the primary artefact** —
  rejected. Prose with a parseable heading gives the same automation with far
  better reviewability; the script parses the Markdown directly.
- **No traceability at all, just tests** — rejected. It is exactly the question
  "which of the things we agreed on actually work?" that the owner needs
  answered, and a test suite alone does not answer it.

## Consequences

- Adding behaviour means editing `docs/requirements/` first. That is deliberate
  friction: a pull request implementing something no requirement asks for is a
  signal to stop and agree on the requirement.
- Status values must be maintained honestly. `Implemented` without a test is a
  failed build, but nothing forces the reverse — a requirement can be built and
  left marked `Accepted`. Review catches that, the script cannot.
- The identifier scheme leaks into test names, which makes them longer and ties
  the suite to the documents. That is the point; the coverage script protects
  against the resulting typos.
- CI gains a third job. It is cheap — a Linux runner and a shell script — and
  independent of the Xcode jobs.
- Reversing this means deleting the directory, the script and the CI job; the
  identifiers in test names would be harmless leftovers.
