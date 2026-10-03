# 0015. Keep what the family chose in UserDefaults, and every position in an evictable store

- **Status:** Accepted
- **Date:** 2026-10-03
- **Deciders:** @berendkleinhaneveld

## Context

[ADR 0012](0012-what-the-local-store-holds.md) decided the shape of the local
store and left its location to
[Q-09](../requirements/open-questions.md#q-09--where-does-local-data-actually-live-on-an-apple-tv).
That question is now answered from published sources rather than from hardware,
and the answer is a constraint, not a location:

- An Apple TV gives an app two durable places: the Keychain, and `UserDefaults`
  up to a warning at 512 KB and termination of the process at 1 MB.
- Everything else an app can write is in `Caches` or `tmp`. tvOS may empty
  either while the app is not running, and publishes no threshold, order or
  schedule for doing so. Other apps' users lose such data in ordinary use —
  some never, some every few days.
- iCloud is Apple's intended answer for anything larger, and NFR-PRIV-01 rules
  it out. NPO's own record of a position is not ours to lean on either
  ([Q-12](../requirements/open-questions.md#q-12--does-playing-through-npo-light-record-progress-at-npo)).

So one SwiftData store cannot be both where ADR 0012's six models live and as
durable as NFR-REL-04 promised. Either the promise shrinks or the data moves.

The data differs in what losing it costs. A pin, a saved episode and a search
term are things somebody chose, and are few. A position is a by-product of
watching, and [ADR 0006](0006-recently-watched-holds-unfinished-items.md) keeps
every one of them for ever; the recent ones are what "where were we?" is asked
about, and the old ones are a courtesy.

There are still no stores in the code, so nothing has to be migrated.

## Decision

**Local data lives in two places, split by what losing it would cost.**

### `UserDefaults` holds what must survive

- Pins, the watch later list and search terms with their picked items — ADR
  0012's `PinnedSeries`, `WatchLaterEntry`, `SearchTerm` and `PickedItem`, as
  records rather than as `@Model` types.
- One `RecentlyWatchedEntry` per item ever started. The row itself (*Kijk
  verder*, FR-HOME-06) is not stored: its order, its cap of twenty and its
  seven-day tail are a query over these entries. An entry holds what cannot be
  computed — which episode to continue with, written when the previous one
  finished, whether anything is left to watch, whether the item was hidden
  (FR-HOME-08), when it was last played, and the cached title.
- A copy of playback positions, as many as fit.
- The settings and the current mode, which ADR 0012 already put there.

All of it stays under **one fixed ceiling, set in code, comfortably below the
512 KB warning**. The lists and the entries come first; positions fill what is
left — first the position each entry points at, so that a film half watched a
year ago keeps its place on the row, then the rest newest first. The oldest of
those is dropped from the copy when a newer one needs the room.

### A SwiftData store in `Caches` holds every position

`PlaybackProgress` is the one `@Model`, in a store at an explicit URL in
`Caches`. It is unbounded, as ADR 0006 decided, and it is what playback and the
home page read. The app never opens a default `ModelConfiguration`: on a device
that resolves somewhere the sandbox refuses.

When the store is missing at launch — tvOS evicted it — it is rebuilt from the
copy in `UserDefaults`. Positions older than the copy reached are gone, and
nothing else is. That is not NFR-REL-05's broken store: nothing the family
chose was lost, so nothing is reset and nobody is told.

### The first build on the television is the test

No hardware experiment precedes the stores. Whether a SwiftData store in
`Caches` opens on our Apple TV is expected from every Core Data precedent and
will be seen on the first device build; a container that fails to open is
already NFR-REL-05's case. The diagnostic app ADR 0012 added under
`tools/storage-probe` was never run on hardware and is removed.

### What ADR 0012 and ADR 0011 keep

The record shapes, the two grains, `mode` as a column, the app's own
identifiers and the four things that stay out are unchanged. So is
[ADR 0011](0011-four-layers-above-the-npo-boundary.md)'s rule for a store:
actor-isolated, mode passed explicitly, `Sendable` values out. A store over
`UserDefaults` owns its defaults the way one over SwiftData owns its
`ModelContext`.

## Alternatives considered

- **The whole of ADR 0012's store in `Caches`, with the promises reworded** —
  the smallest change, and rejected: it makes the family's pins as losable as a
  thumbnail, on evidence that such stores do get emptied.
- **Lists in `UserDefaults`, positions only in `Caches`** — the first form of
  this decision. Rejected because the positions most likely to be wanted are
  the recent ones, they are small, and there is room for them.
- **`UserDefaults` only, no SwiftData store** — not rejected so much as not yet
  earned. At ADR 0006's hundred bytes a position, a few thousand fit under the
  ceiling, and a household may never watch its way past that. It would also
  undo the persistence technology AGENTS.md and ADR 0011 are written around.
  Revisit once the real size of a record and the family's real numbers are
  known.
- **iCloud key-value store or CloudKit** — what Apple intends, and forbidden by
  NFR-PRIV-01.
- **The Keychain as a database** — durable, and it is not one.
- **Running the probe first** — rejected by the owner. It could show that the
  store opens and survives a reboot; it could not show that tvOS will not evict
  it, which is what the decision turns on.

## Consequences

- **NFR-REL-04 is kept for what matters and reworded for the rest.** "Survives
  relaunch" holds as written for FR-HOME-02, FR-LATER-01, FR-MODE-01 and
  FR-SEARCH-04. FR-HOME-11 no longer says that only erasing discards a
  position: eviction can discard an old one.
- **ADR 0006's unbounded store is unbounded only while tvOS leaves it alone.**
  What is guaranteed is the recent positions. Its one-way consequence — a
  discarded position cannot be recovered — now has a second cause.
- **Positions are written twice.** The store and the copy can disagree after a
  hard stop between the two writes; the store is the authority when it exists.
  `UserDefaults` rewrites its whole file on a change, so how often the copy
  follows the store during playback (FR-PLAY-03) is a cost to weigh in the
  playback store's pull request, not something to do at every interval by
  default.
- **An uncapped list sits in a capped container.** FR-LATER-06 says watch later
  is not capped, and pins have no cap either. At a few hundred bytes an entry
  that is thousands of entries away, and the lists take precedence over
  positions — but the ceiling is real, and a store must refuse a write that
  would cross it rather than let tvOS terminate the app.
- **Erasing has two places to clear** (FR-SET-04, NFR-PRIV-04): ADR 0012's one
  coordinator deletes from both, per mode, or an erased position comes back
  from the copy at the next eviction.
- **NFR-PERF-03's large-store fixture still applies**, to the SwiftData store.
- **The Simulator still lies.** It writes anywhere and evicts nothing, so the
  rebuild path is proven by a test that deletes the store between launches, not
  by using the app.
- **Reversing this is cheap in one direction.** Moving a list from
  `UserDefaults` into a store is a migration of a few kilobytes; nothing here
  can make `Caches` durable.
