# 0006. Twenty unfinished items, over positions that outlive the row

- **Status:** Accepted
- **Date:** 2026-09-01
- **Deciders:** @berendkleinhaneveld

## Context

`FR-HOME-06` described the recently watched row as "capped at a fixed number of
items" and left the number, the scope of the cap and the lifetime of an entry
unwritten. Three things were therefore undecided: how many items, whether the
cap counts per mode or across the household, and whether anything expires by
age. A fourth fell out of them — what happens to an item's playback position
when its tile is dropped, which `FR-HOME-08` answers only for the case where
the user removes the item deliberately.

Watch later (ADR 0005) made the question worth settling now rather than later:
the home page has three rows competing for the screen, and the middle one was
the only list in the app with no stated retention rule.

There is still no production code, so nothing has to be migrated.

## Decision

The recently watched row is **twenty unfinished items per mode, ordered by when
they were last played, with no expiry by age**. Finishing something takes it
off the row — an episode finished mid-series leaves the item pointing at the
next episode, an item with nothing left to watch leaves the row entirely.

The **playback positions outlive the row.** An entry pushed off the end by the
cap keeps its position, so finding the item again through search resumes it. A
position is discarded only when the user removes the item by hand
(`FR-HOME-08`) or erases local data (`FR-SET-05`).

The requirements are `FR-HOME-12` to `FR-HOME-14`. `FR-HOME-06` is superseded
by `FR-HOME-12` and `FR-HOME-07` by `FR-HOME-13`.

## Alternatives considered

- **Expiry by age, with or without a minimum kept** — rejected. A half-watched
  film from a year ago is exactly what somebody means to find, and an age rule
  punishes the household that watches least. The cap already bounds the row.
- **A cap shared across both modes** — rejected. The stores are per mode
  (`FR-MODE-05`), and a shared budget would let heavy kids viewing crowd the
  adult row out of its own home page.
- **Making the cap a setting** — rejected for now. `FR-SET-02` holds three
  timings the family will plausibly want to tune; a row length is a number to
  get right once, in code, the way the completion threshold is.
- **Keeping finished items on the row** — rejected. Twenty slots are worth more
  to live threads than to a record of what is done, and replaying is a
  deliberate act that search serves.
- **Discarding the position when an entry is evicted** — rejected, though it is
  the tidier option; see the consequence below. Being crowded out by twenty
  newer things is not the user saying "forget this".
- **Bounding the position store separately, at a larger ceiling** — rejected as
  a ceiling nobody would ever notice being hit, bought with a second eviction
  policy to write, test and explain.

## Consequences

- **The position store grows without an upper bound.** It is the only local
  store in the app that does. A position is an identifier, a time offset and a
  timestamp — on the order of a hundred bytes, so a decade of family viewing is
  megabytes, not gigabytes — and `FR-SET-05` still erases all of it on request,
  so `NFR-PRIV-04` holds. What it does mean is that queries against that store
  must stay indexed by item and mode rather than scanning it, and that
  `NFR-PERF-03`'s home-page timing has to be measured with a store far larger
  than the twenty rows on screen.
- Finishing is now a fan-out of three: it advances a pinned tile
  (`FR-HOME-04`), removes a watch later entry (`FR-LATER-07`), and removes or
  advances a recently watched entry (`FR-HOME-13`). One place should observe
  the threshold and drive all three.
- "Watched" and "has a position" become separate facts. A finished item has no
  row entry but is still marked watched, and the next-episode logic reads the
  watched state, never the row.
- Reversing the retention rules is cheap — they are a constant and a predicate
  over a store that keeps everything. Reversing the decision to keep positions
  is not, in the sense that positions discarded by an earlier version cannot be
  recovered; that direction is one-way.
