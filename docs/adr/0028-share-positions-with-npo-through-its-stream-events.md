# 0028. Share playback positions with NPO through its stream events

- **Status:** Proposed
- **Date:** 2026-10-06
- **Deciders:** @berendkleinhaneveld

## Context

Until now nothing about viewing left the television. NFR-PRIV-01 said so,
[ADR 0014](0014-each-mode-browses-as-an-npo-profile.md) leaned on it, and
[Q-12](../requirements/open-questions.md#q-12--does-playing-through-npo-light-record-progress-at-npo)
confirmed that it held: NPO keeps a position only when an app reports one. The
cost is that the television and NPO's own apps do not know about each other.
An episode watched here is unwatched on a phone, and the other way round.

The owner decided to give that up for positions: the app is to read what NPO
knows and to tell NPO what it plays.

[Q-13](../requirements/open-questions.md#q-13--how-is-a-playback-position-reported-to-npo)
found how NPO works, from three captures of its iPhone app and one event sent
by hand:

- **There is no progress endpoint.** NPO takes a profile's positions from the
  analytics events its player posts to `topspin.npo.nl`: the position in the
  last stream event is the position it gives back, to the last decimal and
  within seconds.
- **Nothing authorises an event.** The account and the profile are named in
  the body and taken on trust. NPO refuses an event that lacks a field it
  needs and names the field; beyond the account, the programme, the position
  and the length it asked for two.
- **A position comes back on the items it belongs to**: in a season's list, on
  a programme's page, in what playing it answers, and on the row of NPO's own
  home page that its apps go on from.
- **That row is a list of its own.** Something is taken off it with a request
  to the app backend, NPO acts on that some seconds later, and the position
  stays. A finished episode leaves it by itself.
- **NPO gives positions and no times.** Nothing says when something was
  watched, or on which device.

## Decision

**The app shares how far something was played with the household's NPO
account, both ways, and nothing else.** The requirements are FR-PLAY-12,
FR-PLAY-13, FR-HOME-12, FR-HOME-13 and FR-SET-05; NFR-PRIV-01 and NFR-PRIV-03
were rewritten to say what is shared.

### Telling NPO

**The app sends the events of NPO's player about a stream, and none of the
others.** Loading, starting, a waypoint for every thirty seconds played,
pausing, resuming, moving to another point, the end, and leaving the player.
Not the page views, the clicks, the choices or the offer NPO's app sends for
every tile it shows: those say what a family looked at, and no position
depends on them.

**An event carries what NPO needs and what it refuses an event without.** The
account, the profile of the mode ([ADR 0014](0014-each-mode-browses-as-an-npo-profile.md)),
the programme under NPO's own name for it, the position, the length, and the
handful of constants with which NPO's app describes itself. No page, no
screen, no address of the stream, no bitrate.

**It is a boundary like the others** ([ADR 0008](0008-one-boundary-around-the-npo-backend.md)):
`PlaybackReporting`, in the app's own terms, with `NPOReports` behind it and a
decorator that logs what NPO did not take ([ADR 0016](0016-log-at-the-seams.md)).
Above it `PlaybackReports` decides what one sitting says and when, from
positions as numbers, the way `PlaybackCoordinator` decides what is written
down.

**A report is sent once and then forgotten.** One that fails is dropped: the
next carries a later position, and nothing that plays waits for it
([ADR 0026](0026-try-a-request-again-only-when-it-is-safe.md) does not try a
POST again either). Nothing is queued for a later launch.

**The generated video is not reported.** A debug build on the simulator plays
a test card under a real programme's name
([ADR 0019](0019-play-a-generated-video-where-fairplay-cannot-run.md)); telling
NPO about it would put positions in the household's account that nobody
watched. Reading works there as everywhere.

### Reading from NPO

**NPO's positions are taken into the television's own store, and every page
goes on reading that store.** A position travels up from the boundary on the
item it belongs to, and is written into `ProgressStore` on its way: by a
catalogue that wraps the others for what lists and pages carry, and by the
player for what playing answers, before it reads where to resume.

**A position is taken when it is news.** The store keeps, beside each
position, what NPO was last seen to have for it. A position NPO reports that
differs from that replaces the television's own; one that does not, changes
nothing. That is the owner's rule — NPO's position wins when it has one —
with the one refinement that NPO has to have said something new to win. It
makes taking a position harmless to repeat, which it has to be: the catalogue
cache ([ADR 0024](0024-keep-what-npo-answered-and-ask-again-behind-it.md))
gives the same season's list for up to a week. And it means that a household
whose network blocks a host with "analytics" in its job description keeps its
own positions, instead of being sent back to an old one at every look.

**The row is the television's, and NPO's row says what is new on it.** What
NPO lists that the row does not continue with is put at its front, in NPO's
order and a second apart, since NPO gives no times. What the row already
continues with keeps its place, and its absence when it was taken off by hand.
An episode is placed in its series by asking NPO, as one started from search
is ([ADR 0020](0020-a-series-continues-where-its-page-was-told.md)). The cap,
the seven days and hiding ([ADR 0006](0006-recently-watched-holds-unfinished-items.md))
are untouched.

**The home page shows what it has and asks behind it**, at most once a minute:
the question is answered with NPO's whole home page, of which one row is read.

### Taking away

**Taking something off the row takes it off NPO's**, with the request NPO's
own app makes. The entry stays hidden on the television, which is what keeps
it away while NPO has not acted yet.

**Erasing a mode empties NPO's row for its profile**, or the row that was just
erased would be filled again at the next look. NPO's row is then left unread
for a minute, for the same reason. NPO keeps the positions themselves, the app
has no way to remove them, and the confirmation says so.

## Alternatives considered

- **Keep to the television** — what the app did. Rejected by the owner: the
  family watches on more than one device.
- **Read NPO's positions and report nothing** — keeps the television out of
  NPO's measurement. Rejected: half of it. What is watched here would still
  be unwatched everywhere else, and NPO's position would be the stale one
  whenever both exist.
- **Send everything NPO's app sends** — the closest imitation, and the least
  likely to stand out. Rejected: it reports browsing, which no position needs.
- **Send only a waypoint and a stop** — the least that was seen to move a
  position. Rejected by the owner in favour of the stream events as NPO's
  player sends them: NPO's row was seen not to list an episode that had only
  a lone waypoint, and the reason was not found.
- **NPO's position always wins** — simpler, and what the rule sounds like.
  Rejected for what it does when a report did not arrive, and to a remembered
  page.
- **The further of the two positions** — never loses progress. Rejected by the
  owner: somebody who went back to watch a part again went back.
- **Show NPO's row instead of the television's** — no merging at all.
  Rejected: the row's rules are requirements with tests behind them, a series
  is one tile here and an episode there, and the home page would need NPO to
  draw itself (NFR-PERF-03, NFR-REL-01).
- **A setting to switch it off** — rejected by the owner for now. It is one
  reporter that says nothing and one catalogue wrapper less, should it come.
- **Keep failed reports and send them later** — NPO would be right more
  often. Rejected: a queue that survives a launch is a store of what was
  watched, kept for NPO's sake, and the next report makes the old one moot.

## Consequences

- **The television is no longer private from the NPO account.** What plays
  here is in NPO's measurement like anything played in its own app, and shows
  up in the household's other NPO apps. That is the point, and it is the end
  of the promise NFR-PRIV-01 used to make.
- **The app depends on an analytics endpoint staying what it is.** It is
  nobody's contract, least of all ours. When NPO changes it, reports fail,
  the log says so, and playback goes on: the television falls back to being
  the only one that knows.
- **The app sends events under a description that is not its own** — NPO's
  brand, platform, player and versions, borrowed as the client identifier is
  ([ADR 0007](0007-sign-in-with-the-device-code-grant.md)). They live in
  `NPOWire` with the rest.
- **NPO can be up to thirty seconds behind**, and where it is, a look at
  NPO's answer before the last report arrived puts the television that far
  back too. The owner accepted that.
- **A page is as fresh as its answer.** Positions on a season's list arrive
  with the list, which the cache may keep for a week. What is being watched
  now is fresh all the same: NPO's row is asked for at the home page, and
  playing something asks about that one.
- **An episode finished elsewhere moves its series on only when NPO's row
  says so.** A finish that arrives with a season's list marks the episode and
  leaves the series' tile where it was until something is played.
- **Erasing is no longer the end of it.** The lists stay empty; the positions
  come back from NPO where the television meets them (FR-PLAY-13).
- **`StoredProgress` has one more column**, optional, which the store takes
  in without a migration ([ADR 0012](0012-what-the-local-store-holds.md)).
- **Kids mode reports as the kids profile.** Whether NPO keeps a row to go on
  from for a kids profile was not seen; with none, nothing is taken in.
- **What a television sends was never captured.** The events are an iPhone's.
  If NPO's Apple TV app describes itself differently, this app does not.
- Reversing it is cheap above the boundary: `NoReports` in place of
  `NPOReports`, and the composition root without the wrapper and without
  `ContinuedElsewhere`. What was reported stays reported.
