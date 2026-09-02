# Open questions

Unknowns that block a requirement. Each is answered by a spike or by the
owner, and each answer lands as a requirement update — plus an ADR when the
decision is architecturally significant (NFR-MAINT-05). Answered questions stay
here, marked as such, so that the reasoning is not lost.

## Q-01 — How does NPO Plus sign-in work on tvOS?

- **Answered:** 2026-09-01 — verified on an Apple TV

**Was blocking:** FR-AUTH-06 — and therefore, in practice, everything.

What does NPO's backend actually support: a device-code pairing flow that lets
the user finish on a phone, a plain credential exchange the TV can do itself,
or something built for their own app only? What does a session look like, how
long does it live, and how is it refreshed (FR-AUTH-03)?

**Answer: the device-code pairing flow, and it is the television's own client
that has it.** `id.npo.nl` advertises
`urn:ietf:params:oauth:grant-type:device_code`, and the grant is enabled per
client — asking for a device code as the captured iOS client is refused with
`400 unauthorized_client`, and asking as the tvOS one is answered. What comes
back is an eight-digit code, a five-minute window, a five-second poll interval,
and a verification page at **`id.npo.nl/koppel`** — a first-party NPO pairing
page, not a stock IdentityServer path, which is the tell that this is the
mechanism NPO's own television app uses. Approving there returns an access
token, an id token and a refresh token.

**It reaches everything.** The tokens are accepted by the same app backend the
iOS client uses — there is no separate television host — and behind it runs the
playback chain this project already mapped
([Q-07](#q-07--does-npos-app-api-serve-playback)). On an **Apple TV HD running
tvOS 26.6** the whole path ran from the code on screen through to a FairPlay
content key and protected content playing.
[ADR 0007](../adr/0007-sign-in-with-the-device-code-grant.md) records the
decision and its costs.

**The two alternatives are recorded as rejected, not as unexplored.**

- *An in-app password form*, driving the website's NextAuth login for the
  session cookie (`__Secure-next-auth.session-token`) the way the Kodi addon
  Retrospect does. It works — a spike reproduced it through to decrypted
  playback — and it was the plan until the capture. It is worse on every axis:
  a password typed with a remote control and handled in our process, and a
  login page that carries a WAF challenge and an encrypted password field built
  by client-side JavaScript.
- *Authorisation code with PKCE through `ASWebAuthenticationSession`*, which is
  what the official iOS app does (`npostart-app-ios-prod`, custom-scheme
  callback, no client secret). It exists on tvOS 16+, but it was never made to
  work and could not be: **no AuthenticationServices UI presents in the tvOS
  Simulator at all** — established with a control experiment against Apple's
  own tvOS sign-in sample, which fails there identically — so the Simulator
  cannot answer the question, and the device-code flow made answering it
  unnecessary. It remains the right shape for a phone or a Mac.

**How long a session lives is still not known**, and deliberately not left
blocking: see FR-AUTH-07, which is written not to depend on the answer. The
tokens last an hour; the refresh token is an opaque handle whose lifetime NPO
keeps server-side and does not return. It carries no session identifier, so
nothing outside the television ends it — signing out elsewhere does not reach
it. Measuring the real figure means holding one token untouched for weeks, and
because refresh tokens are single-use and rotate, it means a store that is not
shared with any other install.

## Q-02 — Which NPO endpoints back search, catalogue and streams?

- **Answered:** 2026-08-31

**Was blocking:** FR-CONTENT-04, FR-SEARCH-02, FR-PLAY-01.

There is no public, documented API. Which endpoints answer a search, list a
series' episodes, and hand out a playable stream URL? Is playback DRM-protected
(FairPlay), and if so, what does the licence exchange need? Are the endpoints
stable enough to depend on, or does the app need a single, easily replaced
boundary around them?

**Answer.** Yes to all three, and yes it needs the boundary.

*Catalogue and search* are one private JSON backend on the website itself,
`https://npo.nl/start/api/domain/…`, authenticated by the same session cookie:
`search-collection-items` answers a search (series and broadcasts are two
separate calls), `series-seasons` and `programs-by-season` walk a series into
its episodes, `program-adjacent` gives the next and previous one,
`page-layout`/`page-collection` and `recommendation-layout`/
`recommendation-collection` back browsing and the home rows, and
`user-profiles`/`user-stream-progress` are the account-scoped ones. Episode
items carry the `productId` that playback needs, so nothing has to scrape the
website's HTML or track its deploy-specific build id.

*Playback* is HLS protected by **FairPlay**. `GET
/start/api/domain/player-token?productId=…` mints a short JWT; `POST
prod.npoplayer.nl/stream-link` — with that JWT raw in `Authorization`, no
`Bearer` prefix — returns a signed CDN manifest URL plus the DRM block: the
FairPlay certificate URL, the licence URL, and a licence token good for about
sixty seconds. `AVContentKeySession` then does the SPC/CKC exchange against
NPO's DRM gateway. The app forwards tokens and never computes one; the OS holds
the CDM. A spike played protected content this way from a plain Swift client,
so nothing here needs device attestation.

*Stability:* this is a private, unversioned backend that can change without
notice, and the licence token's sixty-second life makes the ordering of calls
part of the contract. All of it therefore sits behind one boundary —
[ADR 0008](../adr/0008-one-boundary-around-the-npo-backend.md).

## Q-03 — How is the youth catalogue identified?

- **Partly answered:** 2026-08-31 — still blocking

**Blocks:** FR-MODE-04, FR-SEARCH-08.

Does the backend expose an age rating, a "Zapp"/"NPO 3" grouping, a dedicated
kids search parameter, or nothing usable? Can a search be constrained
server-side, or does the app have to filter results itself — which would mean a
result set that mixes in adult content and needs care?

**What the Q-02 spike settled.** Three mechanisms exist and one is missing.

1. A **youth collection**: the home layout has a `youth` collection key, and
   pages are addressable by id through `page-layout`, so a Zapp-like grouping
   is plausibly one request.
2. **NPO's own profiles — now the front-runner.** The app backend returns each
   profile with a *target group*, a *type*, a *UI type* and a parental-control
   flag, and every request carries the active profile. Those fields only mean
   something if a kids profile sets them differently, in which case the backend
   applies NPO's own definition of the youth catalogue and kids mode becomes a
   profile choice rather than a filter of ours (FR-MODE-04).
3. **Per-item age data**: items carry an age rating and NICAM classification,
   and `program-adjacent` accepts an `ageRestriction` parameter.

**What is missing is the one FR-SEARCH-08 needs.** The search endpoint takes a
query, a search type, a party id and a subscription type — **no age or
catalogue parameter is known**. Unless one turns up, a kids-mode search has to
constrain itself another way: search within the youth catalogue rather than
across everything, or filter results on age rating, which is a weaker
guarantee. FR-SEARCH-08 already allows for this ("where the backend allows
it"), but the choice is real and is not made yet.

**How to answer the rest:** one signed-in session, three calls — `user-profiles`
to see whether a child profile exists and what marks it, a home layout for a
child profile against one for an adult profile, and a search for a term that
matches both adult and children's programmes. It is an hour's work and it
decides how FR-MODE-04 and FR-SEARCH-08 are built.

## Q-04 — What counts as "near the end"?

- **Answered:** 2026-08-30

**Was blocking:** FR-PLAY-04.

Is an episode finished at 95% of its duration, or with less than a fixed number
of seconds remaining? Dutch broadcast episodes often end with a long trailer or
credits, which argues for a generous threshold; a short children's episode
argues against a fixed number of seconds.

**Answer.** The later of the two: 95% of the duration, or the point where 90
seconds remain. The percentage governs short items, the fixed remainder governs
long ones. It ships as one named constant (FR-PLAY-04) and is meant to be
adjusted once the family has lived with it — a tuning change, not a new
decision, so no ADR.

## Q-05 — What language is the interface in?

- **Answered:** 2026-08-30

**Was blocking:** NFR-A11Y-05, now superseded by NFR-I18N-01.

Dutch is the obvious answer for the family; English would make the project
easier for other people to contribute to. Localising from the start costs
little; retrofitting costs a sweep of every view.

**Answer.** Dutch first, but properly internationalised from the very first
view, so another language is a catalogue entry rather than a refactor. That is
more than a choice of words — it constrains how every string, date and quantity
is produced — so it became its own requirement area
([nfr-localisation.md](nfr-localisation.md)) and
[ADR 0004](../adr/0004-dutch-first-localised-from-the-start.md).

## Q-06 — Is there a design wireframe to follow?

**Blocks:** nothing yet, but it shapes every view.

The owner mentioned a wireframe made with Claude. It is not in this repository,
and it was not shared with this session. Until it turns up, the layout
requirements here are described in words only.

**How to answer:** the owner shares the wireframe — as an artifact link, an
export committed under `docs/design/`, or a fresh one — and the layout
requirements are checked against it.

## Q-07 — Does NPO's app API serve playback?

- **Answered:** 2026-08-31 — **yes**

**Was blocking:** whether sign-in could drop the password form at all
([Q-01](#q-01--how-does-npo-plus-sign-in-work-on-tvos)).

The official iOS app authenticates with OAuth tokens rather than the website
session cookie. Does the backend those tokens are for also hand out streams?

**Answer: yes, and the app's playback chain is the one this project already
mapped.** A capture from sign-in through an NPO Plus episode playing, with every
host on the path decrypted, shows the app backend minting a player token for a
caller presenting a bearer access token, and then the same player service, CDN,
FairPlay certificate and licence gateway the website uses. The app never calls
the website's API.

Three details that matter beyond the sign-in question:

- **Entitlement, age rating and resume position arrive with the list.** Items in
  a page response carry the product id, an entitlement indication, an age
  restriction with content warnings, and a stored progress value — so a tile can
  be rendered, gated and resumed from one request (FR-CONTENT-06, FR-HOME-06).
- **Every request carries the active profile**, and profiles carry a target
  group and a UI type — the strongest lead yet for
  [Q-03](#q-03--how-is-the-youth-catalogue-identified).
- **The next episode comes back with the player token**, which is most of what
  autoplay needs (FR-PLAY-05, FR-PLAY-07).

This is what made a token-based sign-in worth pursuing, and
[ADR 0007](../adr/0007-sign-in-with-the-device-code-grant.md) rests on it: the
token path is not a second playback system to work out, it is a better door
into the one already understood. A device-code token from the television client
was afterwards confirmed to open the same door — the same backend, the same
player token, the same licence gateway — so the answer holds for the flow
actually chosen and not only for the iOS one it was captured from. The
wire-level contract is in the companion recon repository (`npo-api`:
`notes/app-api.md`).

## Q-08 — What does an account without NPO Plus look like?

- **Answered:** 2026-09-02 — by decision, not by evidence

**Was blocking:** FR-AUTH-08 — the exact check, not the decision behind it.

NPO light requires an NPO Plus subscription and signs out an account that does
not have one (FR-AUTH-08). Every capture and every prototype run so far used a
**premium account**, so we know precisely what having Plus looks like and have
never once seen what not having it looks like.

What is known: `GET /account` returns `subscriptionType: "premium"` alongside an
`activeSubscriptionGuid`, `GET /subscription` returns
`{type: "premium", premiumType: "continuous", paymentMethod}`, and items carry a
compound `contentIndication` naming both the content and the account, such as
`premiumContent_premiumAccount`.

What is not known is everything on the other side of that: which field is the
authoritative one, what value it takes for a free account, whether
`/subscription` answers at all without one or returns an error, whether
`activeSubscriptionGuid` is simply absent, and how a lapsed or paused
subscription differs from one that never existed. A check written against
guessed values would fail in the worst possible direction — either signing out
a paying subscriber, or letting a free account through into exactly the
advertisement handling FR-AUTH-05 exists to avoid.

**Decision: assume the absence.** `subscriptionType` of exactly `premium`
means NPO Plus; every other value — a different string, an empty one, a missing
field — is treated as a free account and signed out (FR-AUTH-08). No capture is
waited for.

This is the fail-closed direction, and it is the right one: an unrecognised
value never admits an account into the advertisement handling FR-AUTH-05 exists
to avoid. **The cost is in the other direction, and it is real.** If NPO renames
the value, adds a tier — a trial, an annual plan, a paused or past-due state —
or moves the authoritative field, then paying subscribers are signed out, and
the app looks broken to exactly the people it is built for. That failure is
loud and quick to diagnose, which is why it is the acceptable one, but it is
not hypothetical: a household's subscription genuinely does lapse and resume.

**Still worth a capture, when a free account is to hand.** Signing in with one
and reading `/account` and `/subscription` would replace the assumption with a
fact, and would also show whether a lapsed subscription is distinguishable from
one that never existed — the two states this assumption cannot tell apart. It
is recorded as a nice-to-have in the recon repository (`npo-api`:
`notes/app-api.md`, and the capture backlog in `notes/app-capture.md`).
