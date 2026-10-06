# 0014. Each mode browses as one of the account's NPO profiles

- **Status:** Accepted — amended by [0028](0028-share-positions-with-npo-through-its-stream-events.md): positions are now sent to the profile, deliberately
- **Accepted:** 2026-10-03
- **Date:** 2026-10-03
- **Deciders:** @berendkleinhaneveld

## Context

Kids mode has to show NPO's youth catalogue and nothing else (FR-MODE-04,
FR-SEARCH-08), and how that catalogue is identified was
[Q-03](../requirements/open-questions.md#q-03--how-is-the-youth-catalogue-identified).

The captures answer it. An NPO account holds profiles, each general or for a
child, and every catalogue request to the app backend names one in a
`profile-guid` header. That header is the entire switch: the same address
answers from the youth catalogue when a kids profile asks, filtered and ranked
server-side. The filter cannot be rebuilt on the television — NPO admits or
drops a whole series, so an episode rated for all ages is absent when its series
is not allowed, and the ratings on single items would let it through.

So the app does not get to choose *whether* to browse as a profile: the backend
wants one on every catalogue call. What is left to decide is which profile each
mode uses, and what happens when the account has no kids profile. NPO's app
creates one with a single request; this app could do the same.

NPO light's own modes are local (FR-MODE-01, FR-MODE-05): its pins, history and
positions are kept on the television and per mode, and never sent to NPO
(NFR-PRIV-01). NPO's profiles are a different thing that happens to line up.

## Decision

**Normal mode browses as the account's general profile, and kids mode as its
kids profile — the first of each kind that NPO lists. Kids mode is unavailable
until the account has a kids profile, and the app never creates one.**

The mapping lives inside the NPO boundary
([ADR 0008](0008-one-boundary-around-the-npo-backend.md)). Above it there is a
`Mode`, passed explicitly to every catalogue method
([ADR 0011](0011-four-layers-above-the-npo-boundary.md)); a profile identifier
never leaves the boundary. The catalogue answers which modes the account can
use, and asking for the kids catalogue without a kids profile is an error of its
own rather than a fallback to the general one.

## Alternatives considered

- **Create a kids profile when there is none** — rejected. It writes to the
  household's NPO account from an app whose promise is that it keeps to itself,
  it has to choose an age band on the family's behalf, and the profile would
  then appear in NPO's own apps with nobody having asked for it.
- **Fall back to the general catalogue in kids mode** — rejected outright. It is
  the one failure FR-MODE-04 exists to prevent, and it would be silent.
- **Filter the general catalogue on the television by age rating** — rejected.
  It is not NPO's rule (see Context), so it would show a child what NPO's own
  app would not.
- **Let the user pick which profile each mode uses** — not now. It is the
  honest answer for a household with several kids profiles in different age
  bands, and it is a settings screen and a requirement of its own. "The first
  one" is a default that can be replaced without changing anything above the
  boundary.

## Consequences

- **Kids mode depends on something made outside the app.** A household that has
  never made a kids profile at NPO gets an explanation instead of a switch
  (FR-MODE-02), and has to go to NPO's app or the website once.
- **The age band is NPO's and the profile's**, not this app's: a kids profile
  set to six shows less than one set to twelve, and NPO light has no say in it.
- **A kids search is padded with titles that do not match**, and nothing marks
  where the matches end. That is NPO's behaviour for a kids profile and it
  arrives with this decision; the search screen has to be built knowing a result
  count is not a match count.
- **Requests are made as a real NPO profile**, so whatever NPO records against
  a profile when a stream is requested, it records against the household's own.
  Whether that includes a playback position is
  [Q-12](../requirements/open-questions.md#q-12--does-playing-through-npo-light-record-progress-at-npo),
  and it bears on NFR-PRIV-01.
- The profiles are remembered per sign-in and asked for again whenever the
  available modes are asked for, so a kids profile made on a phone is picked up
  without signing in again.
- Reversing it means changing one type inside the boundary; nothing above it
  knows a profile exists.
