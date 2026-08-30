# Performance

Prefix `NFR-PERF`. These are budgets, not aspirations: each one is stated so
that a test can fail when it is missed.

## NFR-PERF-01 — Keystroke to character on screen

- **Status:** Accepted

While typing in search, the time between a keystroke and the character being
rendered stays under **50 ms**, independent of network latency (FR-SEARCH-03).

**Acceptance criteria**

- The search view model's "text changed" path performs no network call, no JSON
  decoding and no store write on the main actor — it schedules them.
- With a fake backend that delays every response by seconds, a burst of
  simulated keystrokes is processed within budget.
- The measurement runs against the view model, not the rendered UI, so it can
  live in the unit test target.

## NFR-PERF-02 — Debounce and cancellation

- **Status:** Accepted

Search issues at most one in-flight request per typing pause, and results that
belong to a superseded query are dropped.

**Acceptance criteria**

- Typing *n* characters quickly issues fewer than *n* requests.
- Starting a new query cancels the previous one.
- A response arriving after its query was superseded changes nothing on screen.

## NFR-PERF-03 — Home page appears quickly

- **Status:** Accepted

After sign-in, the home page renders from cache within **1 second**, before any
network response has arrived (FR-CONTENT-04).

**Acceptance criteria**

- With a populated cache and no network, home renders its rows.
- A background refresh updates the rows in place without a visible reload or a
  focus jump.

## NFR-PERF-04 — Bounded memory

- **Status:** Accepted

Browsing does not grow memory without limit: artwork and catalogue caches have
a fixed ceiling and evict.

**Acceptance criteria**

- The artwork cache has a documented maximum size and evicts least-recently
  used entries.
- Scrolling a long episode list repeatedly does not increase steady-state
  memory.

## NFR-PERF-05 — Nothing heavy on the main actor

- **Status:** Accepted

Networking, decoding, persistence and image decoding happen off the main actor
throughout the app, not only in search.

**Acceptance criteria**

- Types doing I/O are not `@MainActor`; UI state types are.
- Isolation is expressed in the type system rather than with
  `@unchecked Sendable` or `nonisolated(unsafe)` (see AGENTS.md).
