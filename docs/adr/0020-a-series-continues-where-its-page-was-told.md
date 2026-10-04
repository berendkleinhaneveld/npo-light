# 0020. A series continues where its page was told

- **Status:** Proposed
- **Date:** 2026-10-04
- **Deciders:** @berendkleinhaneveld

## Context

A series' page offers the episode to continue with (FR-CONTENT-03), opens on
its season (FR-CONTENT-07), and the home page is to do the same for a pinned
series and on the *Kijk verder* row (FR-HOME-04, FR-HOME-06).
[ADR 0015](0015-local-data-in-two-places.md) decided what is kept for that —
one entry per item started, holding the episode to continue with, "written
when the previous one finished" — and not who writes it, or from what.

Three facts limit the options:

- A position is kept per episode and says nothing about its series
  ([ADR 0012](0012-what-the-local-store-holds.md)). Working out the next
  unwatched episode from positions alone means fetching every season of a
  series that may have 27.
- A list does not name the series an episode belongs to
  ([Q-10](../requirements/open-questions.md#q-10--does-a-programme-in-a-list-belong-to-a-series)).
  Only the series' own page knows, for the episodes it lists.
- NPO lists the seasons of most series first to latest, and of a programme
  with a season for each year latest to first, and says which in the page's
  `programSort`. Seen in the app's own request log: twenty seasons of a drama
  ascending, eleven of a daily programme descending.

## Decision

**Playback writes the entry, and whoever starts playback says where in the
series the episode is.** The series' page hands the player a `SeriesPlace` —
the series and the episode's season. `PlaybackCoordinator` then:

- records the series as continuing with that episode when its stream starts,
  whichever episode it continued with before;
- when the episode passes the completion threshold (FR-PLAY-04), asks the
  catalogue which episode follows (`EpisodeOrder`) and records that one, or
  records the series as finished when none does.

A single programme is an item of its own: search results say that it stands
alone, it is recorded under its own identifier, and finishing it finishes the
item without asking NPO anything. An episode from search results, whose series
nobody named, keeps its position and moves no series.

**The row is a query, as ADR 0015 said.** *Kijk verder* is worked out from the
entries when the home page is drawn — not hidden, not finished more than seven
days ago, newest first, twenty — and a pinned series' tile is read from the
same entry. Taking an item off the row marks its entry and touches nothing
else; starting it again writes a new entry, which is not marked.

**A position keeps the length of what was played**, so that a tile can show
how far in it is without asking NPO: a season's list does not carry it.

**The boundary says which way NPO's list of seasons runs.** `SeriesDetail`
keeps the seasons as listed, for the picker, and answers the broadcast order
from them. The next season is taken from that order, never from the list's,
and the series is asked for it at a season's end rather than carried along
from when the episode was started.

**When NPO cannot say what follows, nothing is recorded.** The series stays on
the finished episode until another is played. Not knowing is not the end of
the series.

## Alternatives considered

- **Working the next episode out when a page opens**, from the positions —
  no entry to keep in step. Rejected: the home page would need the network to
  name a tile, and a long series a fetch per season.
- **Reading the series from NPO's answer to playing an episode**, which names
  it — would cover episodes from search. Not rejected, deferred: it names the
  series by slug, and the app knows a series by its identifier. It is the
  way to close the gap below.
- **Finding the follower when playback starts**, so that finishing needs no
  network — rejected as a request made for every episode started, to save one
  for those finished.
- **Treating the list's order as broadcast order** — what the code assumed.
  Wrong for every programme listed latest first: the last episode of 2025
  would have been followed by nothing.

## Consequences

- The series' page opens on the right season and names the right episode
  without asking NPO for anything but the page and that season.
- Finishing an episode costs one request for its season's list, and two more
  at a season's end. They are made while the stream is still playing.
- A pinned series nobody started has no entry, so its tile cannot name its
  first episode without the network: it opens the series' page, and FR-HOME-04
  stays `Accepted`.
- The position's `@Model` gained an optional attribute. SwiftData adds it to
  a store that is already there; a store it cannot open is started over and
  filled from the copy, as before.
- **An episode started from search does not move its series on**, and its
  series does not appear as started. FR-PLAY-09 says so. It stays `Accepted`,
  as does FR-CONTENT-03, whose single programme has no page yet.
- **Which way the seasons run is inferred from `programSort`**, which is
  about episodes. The two agreed on the two series looked at; a series where
  they differ would be followed in the wrong direction at a season's end.
- For a series nobody started, the page offers the first episode of the
  season NPO lists first. For a daily programme that is the first of this
  year, which is neither the series' first nor its latest: what such a
  programme should offer is a question for the requirements.
- An unavailable episode is not skipped yet (FR-CONTENT-02): nothing in a
  season's list says that it is.
