# 0021. Show the system player through its view controller

- **Status:** Proposed
- **Date:** 2026-10-04
- **Deciders:** @berendkleinhaneveld

## Context

FR-PLAY-05 asks that the next episode starts by itself and that an overlay
names it and offers to stop. The player was SwiftUI's `VideoPlayer`
(FR-PLAY-01). While it plays it holds focus: a SwiftUI button drawn over it
cannot be reached with the remote, and `VideoPlayer` has no way to add one
that can.

The system player itself has one. `AVPlayerViewController` shows its
`contextualActions` as buttons over the video, focused and selectable while
the transport bar is hidden — what other apps use for "skip intro".

## Decision

**The player is `AVPlayerViewController`, wrapped in a representable
(`SystemPlayer`).** It is the same player `VideoPlayer` shows, with the same
transport controls, subtitles and audio tracks, so FR-PLAY-01 holds as before.

**The offer to stop is a contextual action; what is said is drawn by the
app.** For ten seconds after an episode started by itself — one named
constant — the player carries a *Stoppen* action, and a notice that cannot
take focus names the episode. The model decides both; the view shows them.

**Going on is the model's.** When an episode reaches its end, `PlayerModel`
asks the coordinator what its series continues with
([ADR 0020](0020-a-series-continues-where-its-page-was-told.md)), plays that,
or says that the sitting is over, on which the player goes away.

## Alternatives considered

- **A SwiftUI button over `VideoPlayer`** — what the wireframe draws.
  Rejected: it does not take focus from the player.
- **Queueing the next item in an `AVQueuePlayer`** — no gap between episodes.
  Rejected: a stream's details are good for a minute (FR-PLAY-11), so the
  next one cannot be fetched an episode ahead, and each episode needs its own
  content-key session.
- **The system's own "up next" proposal
  (`AVContentProposal`)** — made for this, and it comes before the episode
  ends rather than after. Not rejected for good: it is what FR-PLAY-06's
  countdown in kids mode may want.

## Consequences

- The notice and the button are in two places on the screen: the system puts
  its action at the bottom right, and the app's notice is at the top left.
- The action appears once the transport bar has hidden, a few seconds into
  the episode. The ten seconds are counted from the start.
- Between two episodes the player is taken down and put up again, with the
  progress indicator in between, while the next stream's details are fetched.
- Kids mode does not go on by itself until it can pause first (FR-PLAY-06).
- An unavailable next episode is not skipped yet, so FR-PLAY-07 stays
  `Accepted`.
- The transition cannot be watched against NPO's streams on the simulator. It
  was watched there with the test card
  ([ADR 0019](0019-play-a-generated-video-where-fairplay-cannot-run.md)).
