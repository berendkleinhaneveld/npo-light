# Maintainability and process

Prefix `NFR-MAINT`. The app is written by coding agents under the repository
owner's supervision, so the guard rails are part of the specification.

## NFR-MAINT-01 — Test-first, and traceable

- **Status:** Accepted

Behaviour arrives as a failing test first, and every requirement marked
`Implemented` is named by at least one test (see the
[README](README.md#linking-tests-to-requirements)).

**Acceptance criteria**

- `./scripts/requirements-coverage.sh` passes: no `Implemented` requirement
  without a test, no test referencing an identifier that does not exist.
- The pull request that implements a requirement flips its status in the same
  diff.
- A test asserts something; an empty placeholder test is not a test
  (AGENTS.md).

## NFR-MAINT-02 — Clean builds, no exceptions

- **Status:** Implemented
- **Verified by:** `scripts/check-lint-exceptions.sh` and the CI pipeline

SwiftLint runs strict and the build treats warnings as errors, with no
disabled rules, excluded paths or inline exceptions
([ADR 0002](../adr/0002-strict-linting-and-warning-free-builds.md)).

**Acceptance criteria**

- `./scripts/lint.sh`, `./scripts/build.sh` and `./scripts/test.sh` pass.
- `scripts/check-lint-exceptions.sh` finds no exception.

## NFR-MAINT-03 — Business logic is testable without the UI

- **Status:** Accepted

Views render state and send intent; decisions live in types that a unit test
can drive directly.

**Acceptance criteria**

- Next-episode selection, the completion threshold, still-watching timing,
  search history and pin ordering are all testable without instantiating a
  view.
- UI tests exist only for flows unit tests cannot cover (AGENTS.md).
- Every view has a `#Preview`.

## NFR-MAINT-04 — No network in unit tests

- **Status:** Accepted

The unit test suite is deterministic and offline: the NPO backend sits behind a
protocol, and tests inject fakes — including slow, failing and
never-responding ones, which NFR-PERF-01 and NFR-REL-02 need anyway.

**Acceptance criteria**

- No unit test makes a real network request.
- The suite passes with networking unavailable.
- Time-dependent behaviour (debounce, countdown, still-watching) is driven by
  an injectable clock, not by sleeping in a test.

## NFR-MAINT-05 — Decisions are recorded

- **Status:** Accepted

Architecturally significant decisions get an ADR
([ADR 0001](../adr/0001-record-architecture-decisions.md)), and requirement
changes are made in this directory before the code follows.

**Acceptance criteria**

- Each answered open question lands as an ADR and a requirement update.
- A requirement is never renumbered or recycled (README).
