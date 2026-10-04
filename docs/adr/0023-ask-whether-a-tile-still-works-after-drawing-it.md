# 0023. Ask whether a tile still works, after drawing it

- **Status:** Proposed
- **Date:** 2026-10-05
- **Deciders:** @berendkleinhaneveld

## Context

Rights expire. A pinned series, a saved film or the episode a series continues
with may be gone by the time the family gets to it, and FR-CONTENT-05 and
FR-LATER-11 ask that its tile says so, keeps its place and can still be
removed.

The home page is drawn from what is kept on the television, without the
network ([ADR 0015](0015-local-data-in-two-places.md), NFR-PERF-03). Nothing
kept says whether NPO still has an item, and there is no catalogue cache yet
to answer from (FR-CONTENT-04).

## Decision

**The rows are drawn first, and NPO is asked afterwards.** When the rows have
been read, the home page asks for the page of what each tile would play — the
episode's, or the series' for a tile that plays none — one after another, in
the background. A tile NPO answers "gone" or "not playable" for is marked
unavailable: it says so, plays nothing, and opens the page that explains.

**Only a clear no marks a tile.** A tile NPO could not be asked about is left
as it was.

**An answer is kept for an hour**, in memory, per mode's home page. Coming
back to the home page within the hour asks nothing.

**Nothing is removed.** An unavailable item stays where the family put it
until they take it off.

## Alternatives considered

- **Asking only when a tile is selected** — no requests for tiles nobody
  touches. It is what happened before: the player said that the item was
  gone. Rejected because the requirement is about the tile.
- **Asking before drawing** — a correct first frame, bought with the
  network on the way to the home page. Rejected by NFR-PERF-03.
- **All tiles at once** — sooner done. Rejected for now: a row of twenty is
  twenty requests, and nothing is waiting for them.

## Consequences

- A launch costs a request per tile, up to a few dozen, after the page is on
  screen. A catalogue cache (FR-CONTENT-04) would answer most of them without
  the network; this decision is to be looked at again when there is one.
- A tile can be wrong for a moment: drawn as playable, then marked. Selecting
  it in that moment ends at the player's own message.
- An episode chosen from a series' list is not checked: the stream is asked
  for, and the player says what is wrong. FR-CONTENT-06 stays `Accepted`.
