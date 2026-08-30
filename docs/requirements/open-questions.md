# Open questions

Unknowns that block a requirement. Each is answered by a spike, and each answer
lands as an ADR plus a requirement update (NFR-MAINT-05).

## Q-01 — How does NPO Plus sign-in work on tvOS?

**Blocks:** FR-AUTH-06 — and therefore, in practice, everything.

What does NPO's backend actually support: a device-code pairing flow that lets
the user finish on a phone, a plain credential exchange the TV can do itself,
or something built for their own app only? What does a session look like, how
long does it live, and how is it refreshed (FR-AUTH-03)?

**How to answer:** a throwaway spike against the real endpoints, plus a look at
what the official tvOS app does. Record the answer in an ADR before writing any
production code.

## Q-02 — Which NPO endpoints back search, catalogue and streams?

**Blocks:** FR-CONTENT-04, FR-SEARCH-02, FR-PLAY-01.

There is no public, documented API. Which endpoints answer a search, list a
series' episodes, and hand out a playable stream URL? Is playback DRM-protected
(FairPlay), and if so, what does the licence exchange need? Are the endpoints
stable enough to depend on, or does the app need a single, easily replaced
boundary around them?

**How to answer:** spike alongside Q-01. Whatever the answer, all of it sits
behind one protocol so that a change is one file (NFR-MAINT-04).

## Q-03 — How is the youth catalogue identified?

**Blocks:** FR-MODE-04, FR-SEARCH-08.

Does the backend expose an age rating, a "Zapp"/"NPO 3" grouping, a dedicated
kids search parameter, or nothing usable? Can a search be constrained
server-side, or does the app have to filter results itself — which would mean a
result set that mixes in adult content and needs care?

**How to answer:** part of the Q-02 spike. Until then, the filter is one
function with a fake in tests.

## Q-04 — What counts as "near the end"?

**Blocks:** FR-PLAY-04 (the mechanism is agreed; only the value is open).

Is an episode finished at 95% of its duration, or with less than a fixed number
of seconds remaining? Dutch broadcast episodes often end with a long trailer or
credits, which argues for a generous threshold; a short children's episode
argues against a fixed number of seconds.

**How to answer:** pick a starting value (proposed: the later of 95% and
"90 seconds remaining"), ship it as one named constant, and adjust it once the
family has used it for a while.

## Q-05 — What language is the interface in?

**Blocks:** NFR-A11Y-05.

Dutch is the obvious answer for the family; English would make the project
easier for other people to contribute to. Localising from the start costs
little; retrofitting costs a sweep of every view.

**How to answer:** owner's call. Either way, strings go in a string catalogue
from the first view.

## Q-06 — Is there a design wireframe to follow?

**Blocks:** nothing yet, but it shapes every view.

The owner mentioned a wireframe made with Claude. It is not in this repository,
and it was not shared with this session. Until it turns up, the layout
requirements here are described in words only.

**How to answer:** the owner shares the wireframe — as an artifact link, an
export committed under `docs/design/`, or a fresh one — and the layout
requirements are checked against it.
