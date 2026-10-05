# 0023. Find out that a tile is gone by selecting it

- **Status:** Proposed
- **Date:** 2026-10-05
- **Deciders:** @berendkleinhaneveld

## Context

Rights expire. A pinned series, a saved film or the episode a series continues
with may be gone by the time the family gets to it, and FR-CONTENT-05 and
FR-LATER-11 ask that this does not break the home page: the tile keeps its
place, can be removed, and selecting it explains.

The home page is drawn from what is kept on the television, without the
network ([ADR 0015](0015-local-data-in-two-places.md), NFR-PERF-03). Nothing
kept says whether NPO still has an item. The only way to know before a tile
is selected is to ask NPO about every tile.

## Decision

**The app does not ask NPO about tiles. A tile is found to be gone when it is
selected.** The player asks for the stream as for anything else, and says that
the item is no longer available when NPO says so. The home page remembers
that for as long as it lives: from then on the tile says that it is
unavailable, plays nothing, and opens the page that explains.

**Nothing is removed.** An unavailable item stays where the family put it
until they take it off.

## Alternatives considered

- **Asking NPO about each tile after the rows are drawn** — the first form of
  this decision, built and then taken out by the owner: a request per tile at
  every launch, for tiles nobody may touch, to say a moment earlier what
  selecting the tile says anyway.
- **Asking before drawing** — rejected by NFR-PERF-03.
- **Keeping what was found gone on the television** — a tile would stay marked
  across launches. Not done: an item that comes back would stay marked too,
  and nothing would ask again.

## Consequences

- The home page makes no requests of its own.
- A tile for something that is gone looks like any other until it is selected
  once. FR-CONTENT-05 and FR-LATER-11 say so.
- After a relaunch, or a switch of mode, a tile found gone looks ordinary
  again until it is selected again.
