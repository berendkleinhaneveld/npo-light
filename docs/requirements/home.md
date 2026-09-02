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

- **Status:** Superseded by FR-HOME-12

Left the cap as "a fixed number of items" and said nothing about what leaves
the row or when. Retired once those were settled.

## FR-HOME-07 — Finishing an episode advances the tile

- **Status:** Superseded by FR-HOME-13

Kept a finished series on the row as a tile saying it was finished. The row is
now unfinished items only (FR-HOME-13), so the requirement was retired rather
than rewritten.

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

## FR-HOME-12 — Recently watched holds twenty items per mode

- **Status:** Accepted

The recently watched row shows items the user played and has not finished, plus
the ones finished in the last seven days (FR-HOME-13), most recently played
first, each showing how far in it is. It holds at most **twenty** items **per
mode**; starting a twenty-first drops the oldest. Nothing else expires by age.

Supersedes FR-HOME-06.

**Rationale.** Twenty is long enough that nothing the family is genuinely
mid-way through falls off, and short enough to travel with a remote. Age is the
wrong axis for something unfinished: a half-watched film from a year ago is
exactly what somebody means to find, and a household that watches little would
be punished for it. Like the completion threshold (FR-PLAY-04), the number is a
starting point meant to be adjusted once the family has lived with it.

**Acceptance criteria**

- Starting playback of an item moves it to the front of the row (FR-PLAY-09).
- A series appears once, not once per episode.
- The cap is one named constant, not a number repeated across the code.
- The twenty-first item pushes out the twentieth, and only that one.
- A finished item still on its seven days occupies a slot like any other; the
  cap does not treat it specially.
- The cap counts per mode: twenty in normal mode and twenty in kids mode, each
  unaffected by the other (FR-MODE-05).
- No unfinished entry is dropped because of its age, however long ago it was
  played, and no sweep runs at launch.
- Progress is shown per tile and matches the stored position (FR-PLAY-03).

## FR-HOME-13 — A finished item stays seven days, then leaves

- **Status:** Accepted

The row is what the family has not finished, plus a short tail of what it just
did finish. An episode finished mid-series leaves the item on the row, pointing
at the next episode. An item with nothing left to watch — a film, or a series
whose last episode is finished — stays for **seven days** after it was
finished, marked as finished, and then leaves.

Supersedes FR-HOME-07, which kept a finished series on the row indefinitely.

**Rationale.** Two things are true at once: twenty slots are worth more to live
threads than to a permanent record of what is done, and an item that vanishes
the moment the credits roll takes the evening's viewing with it — "what was
that film called?" is a question asked days later, and a family member who was
not in the room deserves to see what everyone else watched. Seven days is long
enough to cover the week and short enough that the row does not silt up.

**Acceptance criteria**

- An episode watched past the completion threshold (FR-PLAY-04) leaves a tile
  that offers the next episode, with no progress shown since it has not been
  started. That item is not finished, so the seven days do not apply to it.
- A film or a fully watched series stays on the row for seven days from the
  moment it passed the threshold, marked as finished rather than showing
  progress.
- On the eighth day it is gone, whether or not the app was opened in between:
  the row never shows an item finished more than seven days ago, rather than
  relying on a sweep having run.
- The seven days are one named constant, alongside the cap (FR-HOME-12).
- Selecting a finished tile opens the item's detail page rather than silently
  replaying it, as a finished pinned tile does (FR-HOME-04).
- Playing it again from there puts it back on the row as a live entry, at the
  front, starting from the beginning (FR-PLAY-02), and the seven days no longer
  apply until it is finished again.
- Leaving the row does **not** discard what was watched: the episodes stay
  marked watched, so the series' detail page and its next-episode logic are
  unchanged (FR-CONTENT-02, FR-HOME-04).
- A pinned series that leaves the row keeps its pinned tile, which says the
  series is finished (FR-HOME-04).
- Removing a finished item by hand (FR-HOME-08) takes it away before its seven
  days are up.
- A device clock that moves backwards does not extend the seven days
  indefinitely: an entry whose finish time is in the future is treated as
  finished now.

## FR-HOME-14 — Falling off the row does not forget where you were

- **Status:** Accepted

An entry pushed off the end of the row by the cap keeps its stored playback
position. Finding the item again — through search, or through a pinned series —
resumes it where it was left.

**Rationale.** The cap is about how long a row is worth travelling, not about
forgetting. Removing an item by hand (FR-HOME-08) is the deliberate act that
throws the position away; being crowded out by twenty newer things is not.

**Acceptance criteria**

- After an item is evicted, playing it from search or from a detail page
  resumes at its stored position (FR-PLAY-02), and its detail page reads
  *Verder kijken* (FR-CONTENT-03).
- Playing an evicted item puts it back on the row at the front, with its
  progress intact.
- Stored positions therefore outlive the row: they are discarded only by
  removing the item by hand (FR-HOME-08) or by erasing local data (FR-SET-05),
  and nothing else prunes them
  ([ADR 0006](../adr/0006-recently-watched-holds-unfinished-items.md)).
