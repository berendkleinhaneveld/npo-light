# 0019. Play a generated video where FairPlay cannot run

- **Status:** Proposed
- **Date:** 2026-10-04
- **Deciders:** @berendkleinhaneveld

## Context

NPO's streams are protected, and the simulator cannot play a protected stream:
creating the content-key session raises an exception nothing can catch, so
`NPOPlayback` fails there on purpose. The double that stood in for it
([ADR 0009](0009-test-doubles-at-two-seams.md)) handed out a player with
nothing loaded.

So nothing that happens *while something plays* could be seen or tested
anywhere but on the television: resuming at a stored position, writing the
position at an interval and at a pause, finishing
([ADR 0018](0018-when-a-position-is-written-and-where.md)). Autoplay and the
still-watching prompt are next, and are the same kind of thing.

## Decision

We play a **test card**: a video the app makes itself, three minutes of a dark
screen with the elapsed time written on it, one frame a second. It is written
with `AVAssetWriter` to the temporary directory the first time it is asked
for. It exists in debug builds only.

`ScriptedPlayback` plays it, and is used in three places:

- **previews, and the app as a UI test launches it**, as before;
- **unit tests** that need a player with something in it — the model's own
  part of resuming and of writing a position is tested against it;
- **any debug build on the simulator**, in place of `NPOPlayback`. Everything
  around it is real there: NPO's catalogue, the session, the stores. Whatever
  is chosen plays the test card.

The time in the picture is the point: a resume is visible, in a screenshot as
much as by eye.

## Alternatives considered

- **A video file in the repository** — simpler to play, but a binary to keep,
  and with synchronised file groups it would be in the app that ships unless
  the project file says otherwise.
- **A public test stream over the network** — the nearest thing to NPO's HLS,
  and rejected: tests must not depend on a host
  ([NFR-MAINT-04](../requirements/nfr-maintainability.md)), and neither should
  an afternoon's work on a train.
- **Each episode's real duration** — would make the completion threshold
  behave as on the television. Rejected for now: a 47-minute file takes time
  to make and to watch. Three minutes puts the threshold at 2:51, within reach
  of a scrub.
- **Leaving the simulator unable to play** — what it was, and why the last
  change could only be verified by its unit tests.

## Consequences

- On the simulator every item is three minutes long and looks the same. A
  position stored there is a position in the test card, in the simulator's own
  store; it never reaches a television.
- The test card is not HLS and not protected. What it cannot show is still
  only seen on the television: the licence exchange and its renewal
  (FR-PLAY-11), the stream's own subtitles and audio tracks (FR-PLAY-01), and
  how a real stream reports its duration.
- A release build on the simulator still fails with
  `BackendError.protectionUnsupported`, as before.
- Unit tests that use it wait for a file to be written once per run, about a
  second. They do not sleep: a seek is awaited, and nothing has to play.
