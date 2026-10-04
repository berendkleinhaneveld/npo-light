# 0018. When a position is written, and where

- **Status:** Proposed
- **Date:** 2026-10-04
- **Deciders:** @berendkleinhaneveld

## Context

[ADR 0015](0015-local-data-in-two-places.md) put every playback position in a
SwiftData store in `Caches` and a copy of the recent ones in `UserDefaults`,
and left three things to the pull request that builds the store:

- how often the copy follows the store while something plays — `UserDefaults`
  rewrites its whole file on a change;
- how much of the shared ceiling the copy may take, given that pins, watch
  later and search history "come first";
- what a position looks like once the item is finished, which
  [ADR 0012](0012-what-the-local-store-holds.md) describes as an offset the
  record "still carries" and FR-PLAY-02 only as "starts from the beginning".

FR-PLAY-03 asks that a hard stop costs seconds and not the episode. The app's
composition root is synchronous, and a store that was evicted has to be filled
from the copy before anything reads it.

## Decision

**The store is written every ten seconds; the copy only where playback rests.**
`PlaybackCoordinator` owns both rules. While something plays, its position goes
to the SwiftData store at a fixed interval (`note`). When playback pauses, is
closed, fails, reaches the end, passes the completion threshold, or the app
leaves the screen, it goes to the store and to the copy (`keep`).

**Each mode's copy has a budget of its own: 128 KB**, about a thousand
positions, newest first, and it also never crosses the shared ceiling of
384 KB. With both copies full a third of the ceiling is still the lists'. A
position that does not fit pushes the oldest out of the copy; the store keeps
them all.

**Finishing clears the offset and sets the finish.** Past the threshold
(FR-PLAY-04) a record has no position to resume and a `finishedAt`. Playing it
again writes an offset beside the finish, which stays.

**A store that holds nothing is filled from the copy on first use**, inside the
store's actor, not at launch. A store that cannot be opened is deleted and
started over, and if that fails the positions live in memory for the run; the
store says that it was reset.

## Alternatives considered

- **The copy at every interval** — the smallest loss, a plist of up to 128 KB
  rewritten every ten seconds for as long as the television is on. Rejected:
  what it buys is the last ten seconds in the one case where the app is killed
  mid-episode *and* tvOS empties `Caches` before the next launch.
- **The copy fills whatever the lists leave**, as ADR 0015 worded it —
  rejected: a full copy would make the next pin the write that is refused. A
  fixed share keeps the promise the other way round.
- **Keeping the offset on a finished record**, as ADR 0012 worded it —
  rejected: playback that stops in the credits would have to be told apart
  from playback of a re-watch stopped halfway, and both are "finished, with an
  offset". Clearing it at the finish makes the offset mean one thing: where to
  resume.
- **Filling the store at launch** — needs an `async` composition root or a
  blocking read on the main actor (NFR-PERF-05).

## Consequences

- A hard stop mid-episode costs up to ten seconds. A hard stop followed by an
  eviction costs that episode's position since its last pause; nothing else.
- Watching something again does not make it unwatched, and a re-watch resumes
  like anything else.
- A position of zero is never written: a stream that failed before it started
  leaves the stored position alone (FR-PLAY-10).
- Nobody is told yet when the store was reset. NFR-REL-05 asks for that, and
  it stays `Accepted` until a screen says it.
- The player's part — seeking to the resume point, the periodic observer, the
  pause and end notifications — cannot run on the simulator, which has no
  FairPlay. It is verified on the television.
