# Reliability

Prefix `NFR-REL`. The living room is not a lab: the network drops, the backend
changes, the TV gets unplugged mid-episode.

## NFR-REL-01 — The app is usable without a network

- **Status:** Accepted

With no network, the app still shows what it knows: the home page renders from
cache and says what cannot be refreshed.

**Acceptance criteria**

- Launching offline with a valid session and a populated cache shows the home
  page (FR-CONTENT-04).
- Actions that genuinely need the network — playback, search — explain that
  rather than failing silently.
- Coming back online refreshes without a relaunch.

## NFR-REL-02 — Every failure has an actionable state

- **Status:** Accepted

No screen can end up as an infinite spinner or a blank page. Every failed
request results in a message the user can act on.

**Acceptance criteria**

- Each loading state has a defined timeout after which it becomes an error
  state.
- Every error state offers a retry, and retrying works without leaving the
  screen.
- Error text says what failed in plain language, without an error code as the
  whole message.

## NFR-REL-03 — Requests time out and back off

- **Status:** Accepted

Requests have timeouts; transient failures are retried with backoff; permanent
failures are not retried in a loop.

**Acceptance criteria**

- A request that does not complete within its timeout fails rather than hanging.
- Retries use increasing delays and a maximum attempt count.
- A 4xx that is not an expired session is not retried.

## NFR-REL-04 — Local data survives a hard stop

- **Status:** Accepted

Killing the app, or the TV losing power, does not corrupt local data or lose
more than the last persistence interval (FR-PLAY-03).

tvOS may also empty the app's caches while the app is not running, and that is
where the full table of playback positions has to live
([ADR 0015](../adr/0015-local-data-in-two-places.md)). What the family chose —
pins, watch later, search history — the recently watched row and the most
recent positions are kept where tvOS does not reach, and survive it. Older
positions do not.

**Acceptance criteria**

- Writes are committed transactionally; a partial write cannot leave an
  unreadable store.
- After a simulated abrupt termination, pins, history and positions are intact.
- After the position store is deleted between launches, pins, watch later,
  search history, the recently watched row and the most recent positions are
  intact, and the app does not report a reset (NFR-REL-05).
- No write takes the app's `UserDefaults` past its fixed ceiling.

## NFR-REL-05 — A broken store recovers instead of crash-looping

- **Status:** Accepted

If the local store cannot be opened — corruption, or a schema the app no longer
understands — the app recovers by resetting local data and continues, rather
than crashing on every launch.

**Acceptance criteria**

- An unreadable store leads to a working app with empty rows, not a crash.
- The user is told that local data was reset.
- Signing in is not required again as a side effect (FR-AUTH-02).
