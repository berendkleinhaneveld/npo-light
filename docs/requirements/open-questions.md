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

- **Answered:** 2026-10-03 — from captures of 2026-09-03

**Was blocking:** FR-MODE-04, FR-SEARCH-08.

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

**Answer: mechanism 2, and it is the whole of it.** Three captures of NPO's
own app — creating a kids profile, then the same search as the kids profile and
as the general one, ninety seconds apart with nothing else changed — show that
the `profile-guid` header alone selects the catalogue. With a kids profile the
same home and search addresses answer from NPO's youth catalogue, filtered and
ranked by a different model, server-side. There is no age parameter because
none is needed.

Three things follow, and the first two are easy to get wrong:

- **The gate cuts at the series, not the episode.** A series rated 9 is gone
  from a profile set to 6, including its episodes that are themselves rated
  for all ages. Re-implementing the gate from per-item ratings would let those
  through. The ratings on an item are display data, never the rule.
- **A kids search is padded.** It returns a full page whether or not a full
  page matches: after the handful of real matches come youth titles that do not
  match the query at all, and nothing marks where the matches stop. A result
  count is not a match count.
- **A kids profile has an age band NPO derives**, from an age or a birth year
  given when the profile is made. One band was seen (six to nine); which other
  bands exist is not known.

**Decided on 2026-10-03:** each mode browses as one of the account's own NPO
profiles — normal mode as its general profile, kids mode as its kids profile —
and **kids mode is unavailable until the account has a kids profile**. The app
does not create one. [ADR 0014](../adr/0014-each-mode-browses-as-an-npo-profile.md)
records it; FR-MODE-02 and FR-MODE-04 are amended to match.

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

- **Answered:** 2026-10-02

**Was blocking:** nothing, but it shapes every view.

The owner mentioned a wireframe made with Claude. It was not in this
repository, and the layout requirements were described in words only.

**Answer: yes, and it lives here.** An interactive wireframe is kept under
[`wireframe/`](../../wireframe/README.md) and published to GitHub Pages from
`master` — [ADR 0010](../adr/0010-publish-an-interactive-wireframe.md). It is
drawn from the requirements rather than the other way round: where the sketch
and a requirement disagree, the sketch is wrong, and anything it settles that
no requirement does is a proposal, listed in its README, not a specification.
So a view is built against the requirements and checked against the wireframe,
and a layout choice taken from the wireframe alone needs a requirement first.

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
wire-level contract is written up with the proof-of-concept, outside this
repository.

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
is recorded as a nice-to-have on the proof-of-concept's capture backlog, outside
this repository.

## Q-09 — Where does local data actually live on an Apple TV?

- **Answered:** 2026-10-03 — by decision, from published sources; not verified
  on an Apple TV

**Was blocking:** NFR-REL-04, and with it every criterion that reads "survives
relaunch" — FR-HOME-02, FR-LATER-01, FR-MODE-01, FR-PLAY-03, FR-SEARCH-04.

**The question.** Getting the refresh token into the Keychain
([ADR 0007](../adr/0007-sign-in-with-the-device-code-grant.md), FR-AUTH-02)
established on hardware that a real Apple TV gives an app no writable durable
directory: `Documents` and `Application Support` are read-only — writing there
fails with `NSCocoaErrorDomain 513` — and only `Caches` and `tmp` are writable,
both evictable. The tvOS Simulator writes to Application Support happily, which
is why this had to be found on a device.

That was recorded as a fact about the *token*. It is a fact about the whole
local store. A default `ModelConfiguration` puts its store in Application
Support, so the store ADR 0012 describes had nowhere to go, and NFR-REL-04
promised a durability that the only writable location does not offer.

**Answer: two places, split by what losing the data would cost.** What the
family chose — pins, watch later, search history — and the entries the recently
watched row is drawn from live in `UserDefaults`, which tvOS keeps. So does a
copy of the playback positions: the ones that row needs, then the most recent,
as many as fit under a fixed ceiling below the 512 KB at which tvOS starts to
object. Every position, including the ones that no longer fit, lives
in a SwiftData store at an explicit location in `Caches`, which tvOS may empty
while the app is not running; when it has, the store is rebuilt from the copy in
`UserDefaults` and only the older positions are gone.
[ADR 0015](../adr/0015-local-data-in-two-places.md) records the decision and
what it costs; NFR-REL-04, NFR-PRIV-01 and FR-HOME-11 are reworded to match.

**What the published sources settle.** Checked on 2026-09-20 and 2026-10-03.

- *What is durable.* Apple's
  [tvOS programming guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/AppleTV_PG/index.html)
  gives an app 500 KB of persistent local storage through `UserDefaults` and
  requires everything else to be purgeable. The current
  [size-limit documentation](https://developer.apple.com/documentation/foundation/userdefaults/sizelimitexceededmessage)
  puts the warning at 512 KB and termination of the process at 1 MB. Apple
  staff [confirmed in 2015](https://developer.apple.com/forums/thread/16967)
  that defaults and the Keychain persist until the app is deleted. Nothing
  found says tvOS 26 changed any of this.
- *What is writable.* An Apple engineer
  [confirmed](https://developer.apple.com/forums/thread/89008) that the 513 is
  a sandbox denial for anything created under `Library`, and named `Caches`,
  `tmp` and the Keychain as what remains. A Core Data store in `Caches` is the
  established pattern: Realm defaults to it on tvOS, and
  [Firestore moved there](https://github.com/firebase/firebase-ios-sdk/issues/2735)
  after failing at startup in `Documents`.
- *When `Caches` is emptied.* Never under a running app. Otherwise, in Apple
  staff's words, [all local storage can be purged before the next launch](https://developer.apple.com/forums/thread/18465),
  generally at a reboot or when space is short. No threshold, order or schedule
  is published.
- *Whether it happens to real households.* It does. Infuse has a
  [forum thread running for years](https://community.firecore.com/t/metadata-cache-keeps-clearing/23689)
  of metadata caches cleared anywhere from once in years to every few days,
  worst on small devices with many apps and video screensavers. Swiftfin's
  users were [signed out](https://github.com/jellyfin/Swiftfin/issues/776)
  "after an extended period or storage becomes low", and it moved its tvOS
  build to defaults alone in April 2026.
  [Kinosail](https://github.com/Kinosail/kinosail/pull/392) keeps its progress
  journal in `Caches` and treats the server as the authority — which
  NFR-PRIV-01 denies this app.

**What stays unknown, and why it no longer blocks.**

- *What a default `ModelContainer` does on a device* — throws, crashes, or
  quietly resolves somewhere writable. Nothing documents it. The app never asks:
  it always names the location.
- *Whether a SwiftData store in `Caches` opens on our hardware.* Nothing says
  so for SwiftData by name; everything says so for the Core Data store beneath
  it. The first build on the television is the test, and a container that does
  not open is the case NFR-REL-05 already has to survive.
- *How often tvOS evicts a store this small.* The reports are of caches far
  larger than a table of positions, and nothing describes the purge order. Only
  living with the app will tell, and the split is chosen so that the answer
  costs little either way.

**The probe was not run.** A separate diagnostic app was written for this
question on 2026-09-20 and validated in the Simulator; hardware testing was
deferred and then judged unnecessary by the owner on 2026-10-03, because the
one thing it could have shown — that the store opens and survives a reboot —
says nothing about eviction, which is what the decision turns on. It was removed
from the repository with this answer; git keeps it.

## Q-10 — Does a programme in a list belong to a series?

- **Answered:** 2026-10-04 — from the app's own request log on an Apple TV
- **Narrowed:** 2026-10-03 — from "what kind of thing is it?"

**Blocked:** telling a single programme from an episode of a series in search
results and on the home page — and with it the detail page of a single
programme (FR-CONTENT-03), what may be saved (FR-LATER-02) and the label
FR-SEARCH-02 asks for. It did not block playing either of them.

**Answer: yes, a list says whether a programme stands alone, and the answer to
playing it says which series it belongs to.** Both leads below held.

- **`target` is the mark.** A programme in a list carries `target: detail` when
  it belongs to no series and `target: player` when it is an episode. In 23
  searches, 477 different programmes: 476 were `player`, and the one `detail`
  was a film, *The Substance*. It is the same split the home page's film rows
  showed.
- **The player call confirms it.** For the film its answer is a `program` with
  no `seriesSlug` and no `seasonSlug`, and neither a `nextProgram` nor a
  `previousProgram`. For three episodes of three series it names the series and
  the season, and the next and previous episode — in broadcast order, across
  the boundary between seasons, with no previous one for the first episode of a
  series.
- **An episode number is not the mark.** 143 of the 476 episodes have no
  `Afl.` in their caption: daily and weekly programmes are listed by date.
- **A list still does not name the series.** Nothing in a search item says
  which series an episode belongs to; only playing it does.

One film is a small sample for the first point. It agrees with the 36 of 40 on
the captured home page, and FR-SEARCH-10 errs on the safe side: a programme
that does not say is shown as an episode.

**The page of a single programme** (FR-CONTENT-03) is `/programs/page/{guid}`:
its title, a line of NPO's own, a long description, its image, and whether NPO
would let it be played. Found by asking, 2026-10-04, not by capturing NPO's
app: the app may ask for it differently. The same page answers for an episode.

*The question as it stood, kept for the reasoning:*

A search or a home row returns two kinds of item that matter: a `series`, and a
`program`. A `program` is anything playable, and on the app backend nothing in
it says whether it stands alone or is an episode of a series, nor which series.

**What this question used to ask, and why it no longer does.** It asked how to
tell a film, a standalone episode and an episode of a series apart. Reading the
related projects showed that the first two are not a distinction NPO makes:

- **NPO's website backend marks series membership and nothing else.** There a
  programme carries a `series` — with a type of its own — together with a
  season key and an episode number, or it carries no series at all. The Kodi
  addon Retrospect reads a missing series as "a single video not belonging to a
  series" and addresses it at `npo.nl/start/video/…`, where an episode lives at
  `npo.nl/start/serie/…/…/…`.
- **There is no "film" kind.** The series types seen are `timeless_series`,
  `timebound_series` and `timebound_daily`. Films exist as curated rows on the
  home page, not as a type.
- **Only POMS, NPO's metadata API, tells a film from a broadcast**, and it
  needs partner credentials ([ADR 0008](../adr/0008-one-boundary-around-the-npo-backend.md)
  already set it aside).

The requirements never treated a film and a standalone episode differently
either — both play directly, both are saved rather than pinned, neither
autoplays — so FR-CONTENT-01 now has two kinds, a **series** and a **single
programme**, and this question is the one that is left.

**Two leads on the app backend, neither proven.**

- A programme item carries a `target` of `detail` or `player`. On the captured
  home page it lines up with series membership: in the two film rows 36 of 40
  items are `detail` with no episode number in their caption, and the other
  four are `player` with one — episodes of a series, such as a Christmas
  special. But the proof-of-concept's notes call `target` a hint for which
  screen to open, and it does not name the series.
- The answer to the player call names a series and a season for the one
  programme it was captured for, which was an episode. Whether those are absent
  for a single programme has not been seen. That call mints a playback token, so
  it cannot be asked for every tile.

**How to answer, when it is needed:** one player call for a film from the home
page, to see whether the series is absent — the proof-of-concept's client can
make it, with no proxy. A capture of NPO's app opening a film is needed only if
the single programme's detail page needs an endpoint of its own. **Deferred by
the owner on 2026-10-03 until something cannot be built without it.** Until
then the catalogue returns a series or a "playable" that does not claim to know
whether it belongs to one, and a playable search result plays straight away.

## Q-11 — What does an item that cannot be played look like?

**Blocks:** FR-CONTENT-06's first criterion.

Items carry an indication of what this account may do with them, and both
values ever seen mean "playable" — free content on a Plus account, and Plus
content on a Plus account. Every capture came from an account with NPO Plus,
and the owner's expectation is that such an account has **no unplayable items
at all**: what is in the catalogue can be played.

**Working assumption, 2026-10-03:** the catalogue does not mark anything as
unavailable from that indication. An item is unavailable when NPO no longer
returns it (FR-CONTENT-05), and a stream NPO refuses is a playback error
(FR-PLAY-10). If an unplayable-but-listed item ever turns up — a geographic
restriction, a withdrawn episode still in a season's list — its shape is the
answer to this question, and FR-CONTENT-06 gets built against it.

**Evidence, 2026-10-04.** Three runs on an Apple TV saw 477 programmes in
search and 281 episodes in season lists. Every one carried one of the two known
indications — `freeContent_premiumAccount` or `premiumContent_premiumAccount` —
and a film with the second played. Nothing unplayable turned up, so the
assumption stands.

## Q-12 — Does playing through NPO light record progress at NPO?

- **Answered:** 2026-10-04 — from the app's own request log on an Apple TV

**Blocked:** nothing; it bore on NFR-PRIV-01 once playback was built.

The player call is made as an NPO profile ([ADR 0014](../adr/0014-each-mode-browses-as-an-npo-profile.md)),
and NPO's answer to it carries that profile's stored position for the
programme. NPO's own app evidently reports positions; whether NPO records one
merely because a stream was requested, without the app reporting anything, has
not been tested. NFR-PRIV-01 promises that positions are never sent to the NPO
account, and that promise is about what this app sends — but if NPO infers a
position from the stream alone, the household's NPO profiles will show what was
watched here, and the requirement should say so.

**How to answer:** play something through the proof-of-concept as a known
profile, without any progress call, and look at that profile's continue-watching
row in NPO's own app afterwards.

**Answer, 2026-10-04: no.** Playing through this app leaves no position at
NPO, so NFR-PRIV-01 holds as it is written.

A stored position does not come with the player call, as the paragraph above
says: it comes with the list. An episode in a season's list carries
`progress: { secondsWatched, fractionWatched }` when NPO has a position for it,
and no `progress` at all when it has none. One episode in 281 had one — three
seconds into a documentary, from NPO's own app — so even a position that small
is kept and shown.

Two episodes were then played through this app as the general profile, and
their season's list fetched before and after:

- a children's episode played to the end: the list two and a half hours later
  was identical, with no `progress` on it;
- a documentary played partway and stopped: the list twenty minutes later was
  identical, with no `progress` on it, while the three-second position on its
  neighbour was still there.

The second is the one that settles it, since NPO might drop the position of a
finished episode. NPO records a position when its own app reports one, and a
stream that is merely asked for and played is not a report.

## Q-13 — How is a playback position reported to NPO?

- **Answered:** 2026-10-06 — from two captures of NPO's own iPhone app, and
  by sending one event from the proof-of-concept

**Was blocking:** nothing that was `Accepted`. NFR-PRIV-01 and
[out-of-scope.md](out-of-scope.md) said that nothing about viewing was written
back to the NPO Plus account, so no requirement asked for this. It had to be
answered before either could be amended to let a position travel between this
app and NPO's own — which they since were (FR-PLAY-12, FR-PLAY-13).

[Q-12](#q-12--does-playing-through-npo-light-record-progress-at-npo) established
that NPO keeps a position only when its own app reports one. How that report is
made was not known: every capture showed a position arriving, and none showed
one being written.

**What the material showed before the answer**

- *Reading.* An item in a list carries
  `progress: { secondsWatched, fractionWatched }` when NPO has a position for
  it (Q-12).
- *The website's `user-stream-progress` is a read.* `POST
  /start/api/domain/user-stream-progress` takes `{ item_ids, partyId,
  profileGuid }` and answers `{ content: [] }`. It is a POST that carries no
  position: it asks for the positions of the items named.
- *The app backend shows no write.* In the app captures the only request to it
  that is not a GET creates a profile. Around playback there is the player
  call, the stream link and the licence exchange, and nothing else.
- *The reference clients do not know either.* Retrospect has a commented-out
  call to the retired `npostart.nl/api/progress/{prid}`, abandoned because the
  write belongs to a profile it never configured. The POMS clients concern the
  media catalogue, not what a viewer did.
- *The lead.* The only requests that carried a position were the website
  player's analytics events to `topspin.npo.nl`, a host the app captures had
  set aside as analytics and never decrypted.

**Answer: through NPO's analytics events, and through nothing else.** The
position NPO stores for a profile is the position in the last stream event its
player sent to `topspin.npo.nl`. There is no progress endpoint: two captures of
the app with that host decrypted show every request it makes while something
plays, and the app backend is only ever read.

The stored value is the event's value to the last decimal, and it follows the
events within seconds:

- the first capture ended on a waypoint at `88.965560839` seconds; the player
  call that opened the second answered `secondsWatched: 88.965560839`;
- an episode started from nothing sent a waypoint at `29.93982882` and, on
  leaving the player, a stop at `49.028738261`. A season list asked for between
  the two carried `secondsWatched: 29.93982882`; the home page six seconds
  later showed 49;
- an episode played to its end showed 2874 on a home page fetched after its
  last waypoint and before its closing events went out, and 2886 — its whole
  length — on the next.

So a waypoint moves the position, and so does what the player sends when it
closes. Which other stream events do is not established.

**What is sent.** One event per request, as JSON, to `POST
https://topspin.npo.nl/mob-event?p={party_id}`, answered `204` with no body.
The website sends the same events to `/web-event`.

- *No authorisation.* No bearer token and no cookie. The account is named in
  the body alone: `parameters.npo` holds `userId`, `profileId`, `pseudoId` and
  `subscription`.
- *The envelope.* `event_type`, `event_id`, `client_timestamp_iso`, `party_id`,
  `session_id`, `is_new_party`, `is_new_session`, `sdk_version`. The
  identifiers are generated by the client, shaped `0:{8 characters}:{32
  characters}`; the party outlives a launch and the session does not.
- *The stream.* `parameters.stream` holds `id` — the programme's `prid` —
  `position` and `length` in seconds, `isLiveStream`, and the player's own
  description of itself: `playerId`, `playerVersion`, `drmType`, `mediaUrl`,
  the two bitrates.
- *The page.* `parameters.topspin` holds the brand, the app's version, a
  `pageId` and the page's `chapters`; `parameters.screen` the screen's size.
- *When.* `streamLoadComplete` and `streamStart` as playback begins, at the
  position it resumes from; `streamWaypoint` every thirty seconds of playing;
  `streamPause`, `streamResume`, `streamSeek` and the buffering pair as they
  happen; `streamComplete` at the end; `streamStop` on leaving the player.
- *Everything else the app does* goes the same way: an `offer` for each tile
  shown, a `click`, a `choice`, a `contentView` for each page.

**NPO takes the event from anyone.** One `streamWaypoint` was sent from the
proof-of-concept for an episode with no position: a made-up party and session,
a user agent of its own, and none of the events that normally surround a
waypoint. Six seconds later the season's list carried that episode with
`secondsWatched: 12.345678`, the position sent.

- *What it took.* NPO refuses an event that lacks a field it needs with `406`,
  and names the field. Beyond the envelope, `parameters.npo` and a `stream` of
  `id`, `position`, `length` and `isLiveStream`, it asked for two:
  `parameters.topspin.brand` and `parameters.topspin.platformType`. No page,
  no screen, no player description, no media URL.
- *The length is taken on trust too.* The event gave a length of 2400 seconds,
  which is not the episode's, and `fractionWatched` came back as the position
  divided by exactly that.
- *Nothing ties the event to a session.* The profile the position landed on is
  the one named in the body, and no token was sent with it.

**What NPO lists to go on with is a row of its own.** A third capture, of
taking something off *Kijk verder* in NPO's app, and a read of the same
profile after it:

- *Taking off is a request of its own.* `DELETE
  /collection/continue-watching-v0/{programme}` on the app backend, as the
  profile, answered `200` with an empty object. The row's name is the one the
  home page gives it.
- *NPO acts on it late.* A home page asked for two seconds after the answer
  still listed the programme; eleven seconds after, it did not.
- *The position stays.* The season's list carried the same position for the
  programme after it was off the row.
- *A finished episode leaves the row by itself.* The one played to its end in
  the second capture was off it an hour later.
- *Not every position is on the row.* The episode given a position by the
  lone waypoint above was not listed, while the episode before it in the same
  series was. Whether the row holds one episode a series, or wants more than
  a waypoint, was not looked into.

**What is still not known**

- *Which of the account fields are needed.* All four of `parameters.npo` were
  sent; whether `profileId` alone would do was not tried.
- *Whether a position can be taken back.* Taking a programme off the row
  leaves it, and nothing was sent to move one to zero.
- *What a television sends.* Both captures are of the iPhone app, which
  describes itself as `npoplayer-ios` on `platformType: app`.
**What acting on the answer would cost.** Reporting a position means sending
NPO's analytics events, with the account and the profile in them, for as long
as something plays — there is no narrower way to do it. That contradicts
NFR-PRIV-01 and the analytics exclusion in [out-of-scope.md](out-of-scope.md)
as they were written, and NFR-PRIV-03 — which is about third parties — would
need to say where NPO's own measurement stands. It also means writing to a
store whose contract is whatever NPO's analytics team needs it to be, under an
identity the server takes on trust — a position can be written to any profile
whose identifiers are known. Whether the app should do this at all is
the owner's decision.

**Decided, 2026-10-06: it does.** The owner chose to share positions with NPO
both ways. [ADR 0028](../adr/0028-share-positions-with-npo-through-its-stream-events.md)
records how; FR-PLAY-12, FR-PLAY-13, FR-HOME-12, FR-HOME-13 and FR-SET-05 are
the requirements, and NFR-PRIV-01 and NFR-PRIV-03 now say what is shared.
