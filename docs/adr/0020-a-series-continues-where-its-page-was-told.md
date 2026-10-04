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
the series, its seasons from the first to the latest, and the episode's
season. `PlaybackCoordinator` then:

- records the series as continuing with that episode when its stream starts,
  whichever episode it continued with before;
- when the episode passes the completion threshold (FR-PLAY-04), asks the
  catalogue which episode follows (`EpisodeOrder`) and records that one, or
  records the series as finished when none does.

Something played without a place — an episode from search results — keeps its
position and moves no series.

**The boundary says which way NPO's list of seasons runs.** `SeriesDetail`
keeps the seasons as listed, for the picker, and answers the broadcast order
from them. The next season is taken from that order, never from the list's.

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
- Finishing an episode costs one request for its season's list, two at a
  season's end. It is made while the stream is still playing.
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
