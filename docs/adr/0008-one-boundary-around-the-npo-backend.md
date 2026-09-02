# 0008. One boundary around the NPO backend

- **Status:** Accepted
- **Date:** 2026-08-31
- **Deciders:** @berendkleinhaneveld

## Context

A spike mapped what NPO light has to talk to
([Q-02](../requirements/open-questions.md#q-02--which-npo-endpoints-back-search-catalogue-and-streams)).
There is no public API. There are two private ones, and they behave differently:

- **A catalogue backend**, authenticated by the access token from
  [ADR 0007](0007-sign-in-with-the-device-code-grant.md). It answers searches,
  lists a series' seasons and episodes, gives the next and previous episode,
  backs browsing and the home rows, and holds the account's profiles and
  playback positions. Its episode records carry the product identifier
  playback needs, so nothing has to scrape the website's HTML or track the
  build identifier that changes on every deploy. There are in fact two of
  these — the website's, behind a session cookie, and the app's, behind a
  bearer token — and they are not equally good: the app backend returns
  entitlement, age rating and a resume position *with the list*, and it is the
  surface NPO maintains for their own televisions. The app uses that one, and
  the choice is invisible above the boundary.
- **A playback chain across three more hosts.** A player-token call mints a
  JWT for one product; a stream-link call on NPO's player host
  exchanges that JWT — raw in the `Authorization` header, without the `Bearer`
  prefix that would make it fail — for a signed manifest URL on a content
  delivery network and a DRM block; the manifest is FairPlay-protected, and the
  licence is fetched from a DRM gateway with a token that lives about **sixty
  seconds**.

None of it is versioned, documented or promised. Some of it is idiosyncratic in
ways that are invisible from a type signature: the missing `Bearer`, the
minute-long licence token, an availability array the client is expected to
honour before it even asks for a stream (FR-CONTENT-06), a licence response
that arrives mislabelled as HTML. The DRM exchange itself belongs to
AVFoundation: the app forwards a certificate and a token, and the operating
system holds everything that matters.

The wire-level detail — endpoints, headers, token lifetimes, the FairPlay
handshake and the captures behind them — is written up in the companion recon
repository (`npo-api`: `API_SPEC.md` and `notes/`), together with the Swift
prototype that played protected content end to end. It is deliberately kept out
of this repository: it contains capture material, and it changes on NPO's
schedule rather than the app's.

The app's other requirements assume this is all replaceable: NFR-MAINT-04 asks
for one boundary, FR-CONTENT-04 for caching that does not know where data came
from, and the requirements for search, home and playback are written in terms
of items and episodes, not endpoints.

## Decision

**Everything NPO-specific lives behind one module with protocol-shaped
entrances, and nothing above it knows an endpoint, a header or a token exists.**

The boundary exposes what the requirements talk about — sign in, search, fetch
an item, list a series' episodes, find the next one, get what is needed to play
this episode now, report progress — in the app's own model types, with its own
errors. Inside it are the endpoints, the JSON shapes, the header quirks, the
availability rules and the FairPlay key handling. Views, stores and the
playback coordinator depend on the protocols; the concrete implementation is
supplied at composition and replaced with a fake in tests.

Two rules follow from what the spike found, and they are the boundary's job,
not the caller's:

- **Stream details are fetched immediately before playback and never cached**
  (FR-PLAY-11). The licence token expires in about a minute; a cached stream
  URL is a bug waiting for a slow start.
- **Availability is decided inside the boundary**, from the item's windows and
  the current time, so a caller asks "can this play now?" rather than
  interpreting NPO's data itself (FR-CONTENT-06).

Playback uses `AVPlayer` with `AVContentKeySession` for FairPlay. The app
implements no decryption, holds no key material, and treats NPO's licence
server as the authority.

## Alternatives considered

- **Call the endpoints from the views and stores that need them** — rejected.
  It spreads a private, unstable API through the whole app and makes the
  requirements' "one file changes" impossible.
- **A generic HTTP client with typed endpoint descriptions, no domain layer** —
  rejected. It abstracts the wrong thing: the difficulty here is not making
  requests, it is the ordering, the expiry and the entitlement rules between
  them. A thin client leaves those with the caller.
- **A local server or proxy of our own** to normalise NPO's API — rejected.
  Another moving part to run, and it puts the family's session on something
  other than the Apple TV, against NFR-PRIV-01.
- **Depend on the POMS metadata API instead**, NPO's cleaner catalogue backend
  — rejected for now: it needs partner credentials NPO issues, and the website
  backend already answers everything without them.

## Consequences

- The app can be developed and tested without NPO: the protocols get fakes, and
  every requirement above the boundary is testable offline.
- When NPO changes something — and being unversioned, it will — the repair is
  inside one module, with the rest of the app and its tests untouched.
- The boundary carries knowledge that is easy to lose: why the JWT has no
  `Bearer`, why stream details are not cached. Those go in comments where the
  code is, because the reason is not visible from the call.
- It costs indirection. Adding a screen that needs a new endpoint means adding
  a protocol method and a fake, not calling a URL — the price of the two points
  above.
- The app's dependency on NPO's private API remains a real risk to the project;
  this decision contains it, it does not remove it.
