# 0031. Ask again when the television wakes, and about a series that was watched to its end

- **Status:** Proposed
- **Date:** 2026-11-15
- **Deciders:** @berendkleinhaneveld

## Context

A page asked NPO when it opened and never again. That is enough for an app
that is opened, used and closed, and an Apple TV is not used that way: it
sleeps with the app in front and wakes, a day later, on the page it was left
on. A series' page left on screen did not show the episode broadcast since;
going back and opening it again did, because that made a new page.

The home page had a second gap, which sleep only made visible. What a series
continues with is written down when an episode is played
([ADR 0020](0020-a-series-continues-where-its-page-was-told.md)), and the home
page reads what is written down ([ADR 0011](0011-four-layers-above-the-npo-boundary.md)).
Once the last episode was watched, the entry continues with nothing, and
nothing but playing an episode changed that: a pinned series somebody was up
to date with said "everything watched" for as long as its own page was not
opened. FR-HOME-04 already asked for the opposite of a programme followed as
it is broadcast.

The cache below the boundary ([ADR 0024](0024-keep-what-npo-answered-and-ask-again-behind-it.md))
already decides how old an answer may be, per kind of programme. What was
missing was anybody asking.

## Decision

**A page asks again when the scene is active again after the background.**
The home page, a series' page and a programme's page each carry `onWake`,
which watches `scenePhase` and, when it becomes `.active` after it was
`.background`, has the page do what it does when it opens. Not after
`.inactive` alone: that is also what a scene is while the app starts and
under the system's own overlays, when a page has only just asked or nothing
can have changed. The models make that safe
to do on a page that is showing: what is on screen stays until an answer
differs, a series' page asks for its shown season again as well as for the
series, and focus is not touched.

**The cache stays the only pace.** A page asks the ordinary question; the
catalogue answers from what it kept while that is young. Waking twice in a
minute costs two reads of a file and no request.

**The home page asks about a series that continues with nothing.**
`NewEpisodes` takes the series whose tile says everything was watched — on
the pinned row and on the recently watched row — and asks the catalogue
whether something follows: the latest episode of a programme NPO lists
latest first, when that was not watched to its end; for any other series the
episode after the last one watched to its end, looked for in its latest two
seasons. What it finds is written to the series' entry, where everything
else reads it. When the entry was played is left alone, so the tile keeps its
place.

It runs behind the rows, wherever the home page already asks NPO what was
started elsewhere: when it opens, when it comes back on screen, and when the
scene becomes active.

## Alternatives considered

- **A timer that asks every half hour while a page is on screen** — current
  without anybody touching the remote. Rejected: nobody is looking at a page
  that nobody touches, and a television left on would ask NPO all night.
- **`UIApplication.didBecomeActiveNotification` in the models** — no view
  code. Rejected: the models would observe the system rather than be told,
  which no other model here does, and `scenePhase` is what the player
  already uses.
- **Build the pages again on waking**, as a mode switch does
  ([ADR 0022](0022-a-mode-switch-builds-the-screens-again.md)) — nothing to
  reload by hand. Rejected: it throws away focus, the shown season and the
  navigation stack, for a list that usually did not change.
- **Ask about every pinned series, not only those watched to their end** —
  simpler to say. Rejected: a tile that offers an episode has something to
  offer, and asking would cost requests to change nothing on screen.
- **Ask about every series in the history that was watched to its end** — a
  series finished months ago would come back to the row with its new season.
  Rejected for now: that is a row of twenty asking about any number of
  series, and nobody asked for it. A pinned series is the way to say "tell
  me".
- **Keep which episode was watched last in the entry** — exact, where two
  seasons is a bound. Rejected: a stored format changes for a case — the
  last watched episode more than two seasons back from the latest — that
  finishing a series does not produce.
- **Let the series' page write the entry when it sees a newer episode** — no
  request from the home page. Rejected: it is the behaviour that was there,
  one step later. The tile would still wait for its page to be opened.

## Consequences

- A page left on screen overnight shows the new episode when the television
  wakes, as late as the cache allows: half an hour for a programme followed
  as it is broadcast, a day for any other series.
- The home page now asks NPO about series nobody selected — up to two
  requests for each tile that says everything was watched, at the cache's
  pace. [ADR 0023](0023-find-out-that-a-tile-is-gone-by-selecting-it.md)
  still holds for availability: a tile is not asked about to find out
  whether NPO still has it.
- Coming back to the home page reads the cache for each such tile: a
  series and a season's list, from disk.
- A series that was watched to its end and gains an episode loses its
  finish date, so its entry is on the recently watched row again as well,
  where it stood, unless it was taken off by hand.
- That the scene's phase reaches the pages is not covered by a test: the
  simulator can be sent to the background, but NPO's stand-in gains no
  episode meanwhile. What a page does when asked again is covered in the
  models.
