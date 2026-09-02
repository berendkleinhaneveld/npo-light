# 0005. Watch later is a separate, episode-level list beside pinning

- **Status:** Accepted
- **Date:** 2026-09-01
- **Deciders:** @berendkleinhaneveld

## Context

The home page has two user-facing lists: **pinned** items, which the family
chose to follow, and **recently watched**, which the app maintains as a
by-product of playing things (FR-HOME-02, FR-HOME-06). Pinning is deliberately
series-level: a pinned series shows one tile, and that tile is always the next
unwatched episode (FR-HOME-03, FR-HOME-04).

That leaves a gap the owner ran into: a single thing you mean to watch once —
this film, that one documentary episode of a series nobody follows. Pinning
the series is wrong (it starts offering every episode, and the tile moves on),
and remembering it in your head is what the app is supposed to replace.

There is no production code yet, so this is settled while it is still free to
settle: no store to migrate, no view to rewrite.

## Decision

Watch later is a **separate list, holding one playable item at a time** — a
film, a standalone episode, or one episode of a series — kept per mode
alongside the pins, the history and the search history. A series cannot be
saved; an episode cannot be pinned. The list is uncapped, ordered
most-recently-saved first, and it empties itself: passing the completion
threshold (FR-PLAY-04) takes an item off it.

It shows as a third home row below recently watched, and the row is hidden
entirely while the list is empty.

The requirements are `FR-LATER-01` to `FR-LATER-12` in
[`docs/requirements/watch-later.md`](../requirements/watch-later.md).
`FR-HOME-01` gains the third row, and `FR-SET-04` the new list among the data
erasing removes.

## Alternatives considered

- **Extend pinning to hold episodes** — rejected. Pinning means "keep giving us
  the next one"; a pinned entry that must instead stay on one episode forever
  makes FR-HOME-04's tile rule conditional on a flag, and the two intentions
  then fight over one row.
- **One curated list with a "following" / "watch later" flag per entry** —
  rejected for the same reason one layer up: every rule about ordering, tiles
  and completion would have to branch on the flag, and the home row would have
  to explain the difference visually.
- **Replace pinning with watch later** — rejected. Following a series is the
  household's main use of the app; a list that empties itself is the wrong
  shape for it.
- **A cap, oldest dropped, like recently watched** — rejected. History is a
  by-product and can be trimmed silently; this list is a set of deliberate
  choices, and dropping one loses something the user asked the app to remember.
- **Remove a saved item as soon as playback starts** — rejected. Something
  started and abandoned halfway is exactly what the family still means to
  watch; it stays until it is finished, appearing in both rows with the same
  progress.

## Consequences

- A third per-mode store, of the same shape as the existing ones: identifiers
  plus a saved-at timestamp, with the mode as part of the key (FR-MODE-05).
  Nothing new about persistence — it is another SwiftData model.
- Completion becomes a fan-out. Passing FR-PLAY-04 already advances tiles and
  drives autoplay; it now also removes a saved entry, so "finished" needs one
  place that observes it rather than three that re-implement it.
- The home page's row count is now dynamic, which touches focus behaviour
  (NFR-A11Y-01): the watch later row appears and disappears under the user, and
  focus has to survive it.
- Saving is offered on four surfaces (detail page, episode list, search result,
  recently watched tile), so the toggle is one component reused, not four
  buttons.
- Reversing this is cheap while the list is empty in the field and expensive
  afterwards: the entries are the family's own choices, so a later merge into
  pinning would have to keep them.
