# Home page

The app's single main page: what the family deliberately chose to watch, and
what they were watching last. Prefix `FR-HOME`.

## FR-HOME-01 — Home is pinned, then recently watched

- **Status:** Superseded by FR-HOME-11

Described a home page of exactly two rows, with no other content row. Watch
later adds a third ([watch-later.md](watch-later.md), FR-LATER-05), so the
requirement was retired rather than rewritten.

## FR-HOME-02 — Pinned order is most recently pinned first

- **Status:** Accepted

The pinned row shows pinned items with the most recently pinned first.

**Acceptance criteria**

- Pinning an item puts it at the front of the row.
- Re-pinning an item that was unpinned moves it to the front.
- The order survives relaunch.

## FR-HOME-03 — Pin a series or a film

- **Status:** Accepted

A series or a film can be pinned from its detail page (FR-CONTENT-03).
Individual episodes cannot be pinned; the series is pinned instead.

**Acceptance criteria**

- Pinning a series from an episode's context pins the series, not the episode.
- A film pins as itself.
- A standalone episode — one belonging to no series — pins as itself.
- Pinning an already pinned item does not create a duplicate tile.

## FR-HOME-04 — A pinned series tile is the next episode

- **Status:** Accepted

A pinned series shows one tile. That tile names the episode that will play —
the next unwatched one — and playing it starts that episode.

**Acceptance criteria**

- With no episode of the series watched, the tile offers the first episode.
- With episodes watched up to and including episode *n*, the tile offers
  episode *n+1* (FR-CONTENT-02).
- With a partly watched episode, the tile offers that episode and resumes it
  (FR-PLAY-02).
- With every episode watched, the tile says so and offers the series detail
  page instead of playing.
- A pinned film's tile plays the film, resuming if there is a stored position.

## FR-HOME-05 — Unpin

- **Status:** Accepted

A pinned item can be unpinned directly from the home page, as well as from its
detail page.

**Acceptance criteria**

- Unpinning from home removes the tile immediately, without leaving the page.
- Unpinning does not remove the item from recently watched, and does not
  discard its playback position.
- The action is discoverable from the remote without a hidden gesture being the
  only route (NFR-A11Y-01).

## FR-HOME-06 — Recently watched, most recent first

- **Status:** Accepted

The recently watched row shows items the user played, most recently played
first, each showing how far in it is.

**Acceptance criteria**

- Starting playback of an item moves it to the front of the row.
- A series appears once, not once per episode.
- The row is capped at a fixed number of items; the oldest entry is dropped
  when the cap is exceeded.
- Progress is shown per tile and matches the stored position (FR-PLAY-03).

## FR-HOME-07 — Finishing an episode advances the tile

- **Status:** Accepted

When playback of an episode stopped at or very near its end, the item's
recently watched tile offers the *next* episode rather than the finished one.

**Acceptance criteria**

- An episode watched past the completion threshold (FR-PLAY-04) leaves a tile
  that offers the next episode.
- The next episode's tile shows no progress, since it has not been started.
- When the finished episode was the last one, the tile says the series is
  finished and does not offer to replay it silently.

## FR-HOME-08 — Remove from recently watched

- **Status:** Accepted

An item can be removed from the recently watched row.

**Acceptance criteria**

- Removing takes the tile away immediately and it does not come back on
  relaunch.
- Removing an item discards its stored playback position, so playing it again
  starts from the beginning.
- Removing does not unpin the item if it is also pinned.

## FR-HOME-09 — Empty states say what to do

- **Status:** Accepted

With nothing pinned or nothing watched, the row explains itself instead of
showing an empty band.

**Acceptance criteria**

- An empty pinned row points at search as the way to find something to pin.
- An empty recently watched row does the same.
- With both rows empty, the home page still gives focus to something usable.

## FR-HOME-10 — Home reflects what just happened

- **Status:** Accepted

Coming back from playback, from a detail page or from search, the home page
shows the current state without a manual refresh.

**Acceptance criteria**

- Returning from playback updates the item's position and its place in the row.
- Returning after pinning shows the new tile.
- Focus lands somewhere sensible after the update rather than jumping to the
  first tile (NFR-A11Y-01).

## FR-HOME-11 — Home is pinned, recently watched, then watch later

- **Status:** Accepted

The home page shows three rows, in this order: **pinned**, **recently
watched**, **watch later**. Search and — in normal mode — settings are
reachable from the same page.

Supersedes FR-HOME-01, which described the first two rows and said no other
content row existed.

**Acceptance criteria**

- Home is the first screen after sign-in (FR-AUTH-01).
- The rows appear in that order, in both modes (FR-LATER-10).
- The watch later row is absent while its list is empty (FR-LATER-05); the
  other two rows show their empty states instead (FR-HOME-09).
- Search is reachable in one remote action from home (FR-SEARCH-01).
- No further content rows exist yet; a discover row is deferred
  ([out of scope](out-of-scope.md)).
