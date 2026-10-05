# Reliability

Prefix `NFR-REL`. The living room is not a lab: the network drops, the backend
changes, the TV gets unplugged mid-episode.

## NFR-REL-01 — The app is usable without a network

- **Status:** Implemented

With no network, the app still shows what it knows: the home page renders from
what is kept on the television and says that NPO cannot be reached.

**Acceptance criteria**

- Launching offline with a stored session shows the home page, when NPO
  admitted the account at an earlier launch: the app goes on with that answer
  until NPO can be asked again
  ([ADR 0025](../adr/0025-go-on-with-the-last-admitted-account-offline.md)).
  Without such an answer the launch says that NPO cannot be reached and
  offers a retry (FR-AUTH-08).
- A page seen before opens from what NPO answered then (FR-CONTENT-04).
- The home page says that NPO cannot be reached, for as long as that lasts.
- Actions that genuinely need the network — playback, search — explain that
  rather than failing silently.
- Coming back online is noticed without a relaunch: NPO is asked again while
  it cannot be reached, and its first answer is acted on as at a launch — a
  subscription that lapsed in the meantime is caught (FR-AUTH-08).

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

- **Status:** Implemented

Requests have timeouts; transient failures are retried with backoff; permanent
failures are not retried in a loop
([ADR 0026](../adr/0026-try-a-request-again-only-when-it-is-safe.md)).

**Acceptance criteria**

- A request that does not complete within its timeout fails rather than hanging.
- Retries use increasing delays and a maximum attempt count.
- A 4xx that is not an expired session is not retried.
- Only a request that changes nothing is retried: a renewal of the session is
  sent once, because its token can be used once (FR-AUTH-07).
- A request that timed out is not sent again, so that no page waits several
  timeouts before it says anything (NFR-REL-02).

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

- **Status:** Implemented

If the local store cannot be opened — corruption, or a schema the app no longer
understands — the app recovers by resetting local data and continues, rather
than crashing on every launch.

**Acceptance criteria**

- An unreadable store leads to a working app with empty rows, not a crash.
- The user is told that local data was reset.
- Signing in is not required again as a side effect (FR-AUTH-02).
