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

- a young answer is given without asking NPO;
- an older one is asked for again, and the new answer kept;
- when NPO cannot be reached, the old answer is given after all;
- when NPO says the item is gone, what was kept of it is removed.

**How long an answer is young depends on what it is about.** The family
mostly watches series that were finished long ago, and now and then the news;
one age for both is either too many requests or an evening's episode missing.
NPO says which programmes are followed as they are broadcast — it calls them
time-bound and lists them latest first, which the boundary already reads
([ADR 0020](0020-a-series-continues-where-its-page-was-told.md)). From that,
three paces:

| Pace | Asked for again after | What |
| --- | --- | --- |
| current | half an hour | a time-bound programme's page, and its latest season |
| running | a day | any other series' page, and its latest season |
| settled | a week | every earlier season, and a programme's own page |

A series' page and its latest season are never settled, because nothing says
that a series has ended: a drama may gain an episode a week, or a season next
year. A season's list does not say what it is a season of, so its pace is
taken from its series when that passed through, kept with the answer for the
launches after, and is the fastest when it is not known.

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
- **One age for everything** — the first form of this decision, at thirty
  minutes. Replaced at the owner's suggestion: too often for a series that
  ended years ago, and the only way to make it less often was to make the
  news late.
- **A week for every series that is not time-bound**, its latest season
  included — what the owner first asked for. Not done as asked: a drama that
  is still running would show this week's episode up to a week late. A day
  for the latest season costs one request a day for a series that is looked
  at daily.

## Consequences

- A page seen before opens at once, also after a relaunch, and without a
  network.
- A new episode can be late in a list that was looked at just before it
  appeared: up to half an hour for a time-bound programme, up to a day for
  any other series. Going on to the next episode reads the same list, so
  autoplay can be that late in seeing it too.
- Which programmes are time-bound is NPO's word, read from the same field as
  the direction of the seasons, on the evidence of two series.
- A programme's page is asked for once a week, and says whether NPO would
  play the programme. That answer can be a week old; the player is what
  finds out for certain.
- A season's list is kept whole, descriptions included: about eighty
  kilobytes for a year of a daily programme.
- An answer kept by one version of the app and not readable by the next is
  treated as not kept.
- The home page still opens on a problem page when NPO cannot be reached at
  launch, because the session is checked first. NFR-REL-01 stays `Accepted`
  for that.
