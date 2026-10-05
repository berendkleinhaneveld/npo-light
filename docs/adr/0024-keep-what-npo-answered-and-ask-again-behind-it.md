# 0024. Keep what NPO answered, and ask again behind it

- **Status:** Proposed
- **Date:** 2026-10-05
- **Deciders:** @berendkleinhaneveld

## Context

Every page asked NPO for everything it shows, every time it opened: a series'
page for the series and then for a season, a programme's page for the
programme. A page seen a minute ago opened on a progress indicator again, and
without a network it did not open at all. FR-CONTENT-04 asks that a screen
seen before can be drawn without a round trip, from a cache that is bounded
and dated.

[ADR 0012](0012-what-the-local-store-holds.md) already said where such a
cache belongs: inside the NPO boundary, keyed in the app's own types, apart
from the stores — it must be evictable where they must not be, and losing it
costs a round trip and nothing the family chose.

## Decision

**A catalogue that keeps answers wraps the one that asks NPO.**
`CachedCatalogue` is a `Catalogue` like any other; nothing above the boundary
knows that there is a cache. It keeps three kinds of answer — a series, a
season's episodes, a programme's page — per mode, since the two modes browse
different catalogues.

**One rule for all three:**

- an answer younger than **thirty minutes** is given without asking NPO;
- an older one is asked for again, and the new answer kept;
- when NPO cannot be reached, the old answer is given after all;
- when NPO says the item is gone, what was kept of it is removed.

**What is kept is also there to show at once.** `Catalogue` gains three
questions that never ask NPO — what is remembered of a series, a season, a
programme — and a page asks them first: it shows what it gets, asks the
ordinary question behind it, and changes only when the answer differs. A
refresh that fails leaves what is shown alone.

**The cache is files in `Caches`**, one an answer, dated by when NPO
answered, under two ceilings: 400 answers and 16 MB. The oldest go first.
tvOS may empty the directory whenever it likes.

**Erasing a mode's data erases its answers too** (FR-SET-04): what was browsed
says something about who browsed.

**Not kept:** search results, which are for what was typed a moment ago;
where an episode sits in its series; which modes the account has.

## Alternatives considered

- **The system's own `URLCache`** — no code of ours. Rejected: NPO's answers
  carry no caching headers to go by, the key would be NPO's address rather
  than the app's own identifier, and the answers would be kept in NPO's shape,
  which ADR 0008 keeps below the boundary.
- **In the SwiftData store, beside the positions** — one place for local
  data. Rejected by ADR 0012: the one thing that must be evictable would
  share a lifetime with what must not be.
- **In memory only** — nothing to bound on disk. Rejected: a relaunch is when
  a cache is most wanted, and a season's list is a hundred kilobytes that
  need not be held.
- **A stream of answers from one question** — "here is the old one, here is
  the new one". Rejected as more than two plain questions need: every caller
  would become a loop.
- **A shorter or longer age** — thirty minutes is a guess. It is how late a
  new episode can show up in a season's list, against how often a page opens
  without waiting.

## Consequences

- A page seen before opens at once, also after a relaunch, and without a
  network.
- A new episode can be up to thirty minutes late in a list that was looked at
  just before it appeared. Going on to the next episode reads the same list,
  so autoplay can be that late in seeing it too.
- A season's list is kept whole, descriptions included: about eighty
  kilobytes for a year of a daily programme.
- An answer kept by one version of the app and not readable by the next is
  treated as not kept.
- The home page still opens on a problem page when NPO cannot be reached at
  launch, because the session is checked first. NFR-REL-01 stays `Accepted`
  for that.
