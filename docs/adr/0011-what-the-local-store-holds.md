# 0011. What the local store holds, and what it does not

- **Status:** Proposed
- **Date:** 2026-09-03
- **Deciders:** @berendkleinhaneveld

## Context

Six requirement areas write to local storage (FR-HOME, FR-LATER, FR-PLAY,
FR-SEARCH, FR-MODE-01, FR-SET-02) and three constrain how (NFR-PRIV-01,
NFR-PRIV-04, NFR-REL-04).
[ADR 0006](0006-recently-watched-holds-unfinished-items.md) settled the retention
rules and one structural fact — positions outlive the row — but not what the
records are, how mode scopes them, or where the catalogue cache sits. Five
feature areas are about to be built on that gap in parallel
([ADR 0010](0010-four-layers-above-the-npo-boundary.md)).

**This decides the shape of the store, not its location.**
[Q-09](../requirements/open-questions.md#q-09--where-does-local-data-actually-live-on-an-apple-tv)
asks whether an Apple TV has anywhere durable to put it, and is open. The shape
holds either way; what changes is whether the durability requirements can be kept
as written.

## Decision

### Six models, two grains

| Model | Grain | Serves |
| --- | --- | --- |
| `PinnedItem` | item | FR-HOME-02, -03, -05 |
| `RecentlyWatchedEntry` | item | FR-HOME-06, -07, -08 |
| `PlaybackProgress` | playable | FR-PLAY-02, -03, -04, FR-HOME-11 |
| `WatchLaterEntry` | playable | FR-LATER-01 to -12 |
| `SearchTerm` | term | FR-SEARCH-04, -05, -07 |
| `PickedItem` | item, under a term | FR-SEARCH-05, -06 |

**Item** is a series, a film or a standalone episode: what is pinned
(FR-HOME-03), and what holds one row slot across a dozen episodes (FR-HOME-06).
**Playable** is a film or a single episode: what carries a position (FR-MODE-05)
and the only thing that can be saved (FR-LATER-02). Both rows *display* an
episode; only the record is series-keyed.

Every record carries the **cached title** its tile needs: FR-CONTENT-05 and
FR-LATER-11 require a tile to render, and be removable, for an item the backend
no longer returns.

`RecentlyWatchedEntry` also carries a **hidden** flag. FR-HOME-08 is a change to
the row and to nothing else: a hidden entry keeps its place in the store and its
positions, is filtered out of the row and out of the cap, and is unhidden by
playing the item again (FR-PLAY-09).

### `mode` is a column, not a container per mode

Stores take it as an argument (ADR 0010) and never read an ambient one, so
FR-MODE-05's scoping is visible in every signature and provable per store.

### Progress carries two independent facts

An `offset` (absent means from the beginning) and a `finishedAt` (absent means
unfinished): ADR 0006's "watched and has a position are separate facts", held in
one record rather than two that can disagree.

FR-PLAY-02 is what needs them independent: a finished item keeps its finish, and
is played from the beginning rather than resumed from the offset it still
carries.

### Identifiers are the app's own

Opaque `ItemID` and `EpisodeID` from the boundary. No `productId` — ADR 0008
makes that a playback detail, and it is the likeliest to change under us.

### Four things stay out

- **The catalogue cache** (FR-CONTENT-04) — bounded and evicting (NFR-PERF-04),
  and lost at the cost of a round trip rather than a user's choice. It lives
  inside the NPO boundary, keyed in the app's own types.
- **Settings and the current mode** (FR-SET-02, FR-MODE-01) — four values in
  `UserDefaults`, each read through a defaulting accessor.
- **Credentials** — the Keychain and nowhere else (FR-AUTH-02, NFR-PRIV-02).
- **Artwork** — a cache, on the same footing as the catalogue (NFR-PERF-04).

### No versioned migration until the first install on the family's television

Before it, a schema change resets local data, and NFR-REL-05 already requires
surviving that and saying so. After it, schema changes are versioned and this
record gets a successor.

## Alternatives considered

- **A container per mode** — attractive: FR-MODE-05 unbreakable by construction,
  and FR-SET-04's per-mode erase a file deletion. Rejected on balance: a container
  swap inside FR-MODE-02's one-button switch invalidates every store handle while
  the user waits, and it doubles NFR-REL-05's recovery path. Revisit if a mode
  leak ever ships.
- **"Watched" as its own model** — rejected: two records that can disagree about
  one episode.
- **The catalogue cache in the same store** — rejected: it would give the one
  thing that must be evictable the same lifetime as the things that must not be.
- **Settings in SwiftData** — rejected: four values do not want a container, and
  FR-SET-02's fallback is easier over `UserDefaults` than over a store that might
  not open.
- **Files instead of SwiftData** — rejected while AGENTS.md names SwiftData, but
  recorded because Q-09 could force it.

## Consequences

- **ADR 0006's unbounded progress store needs indexes on mode and identifier.**
  NFR-PERF-03's one-second home render has to be measured against a store far
  larger than twenty rows, so a fixture seeding thousands of positions belongs in
  the home page's pull request.
- **Cached titles mean a stale copy of NPO's data by design**, refreshed whenever
  an item is fetched anyway. It is what FR-CONTENT-05 renders.
- **Erasing is one coordinator's job**: a delete across five models filtered by
  mode, plus both caches, or NFR-PRIV-04 does not hold.
- **If Q-09 finds nowhere durable, this schema survives and its promises do not.**
  NFR-REL-04 and every "survives relaunch" criterion would need rewording.
