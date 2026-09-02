# 0007. Sign in with the device-code grant, approved on a phone

- **Status:** Accepted
- **Date:** 2026-09-01
- **Deciders:** @berendkleinhaneveld

## Context

Sign-in was the project's one genuinely unknown piece
([Q-01](../requirements/open-questions.md#q-01--how-does-npo-plus-sign-in-work-on-tvos)):
NPO publishes no API, and everything else in the app waits behind it. A recon spike answered
it by capture and experiment, and then by building the client twice — once on macOS, once on
tvOS — and running it on a real Apple TV. Three findings decided this, in the order they
arrived.

**The platform does not offer a sign-in; it offers a menu.** tvOS's whole contribution is
`ASAuthorizationCustomMethod`, which has three values: the TV-provider single sign-on (NPO is
not a TV provider, it runs its own accounts at `id.npo.nl`), restoring an in-app purchase (the
subscription is NPO's, not the App Store's), and `.other` — "the app presents its own UI".
Apple's own tvOS sign-in sample recommends iCloud Keychain autofill, which is gated behind an
associated-domains entitlement that only whoever controls `npo.nl` can claim. So everything
after the user picks `.other` is ours to build, and the platform neither constrains the choice
nor helps with it.

**A browser flow is not the answer here.** The obvious candidate was authorisation code with
PKCE through `ASWebAuthenticationSession`, which does exist on tvOS 16+ and which the captured
official iOS app uses (`npostart-app-ios-prod`, custom-scheme callback, no client secret). On
tvOS it is a reduced API that hands the login to a nearby device, and it was never made to
work: in the Simulator it fails silently, and a control experiment with Apple's own sample
showed that **no** AuthenticationServices UI presents there at all — so the Simulator cannot
answer the question either way, and the flow stayed unproven on hardware. It was not needed.

**The device-code grant is available, and it is the television's client that has it.**
`id.npo.nl` advertises `urn:ietf:params:oauth:grant-type:device_code`, and the grant is
enabled per client: `POST /connect/deviceauthorization` refuses the captured iOS client with
`400 unauthorized_client` and answers the tvOS one with `200`. It returns an eight-digit code,
a five-minute window, a five-second poll interval, and a verification page at
**`id.npo.nl/koppel`** — a first-party NPO pairing page, not a stock IdentityServer path.
That is the mechanism NPO's own television app uses.

It was then verified end to end on our own account, and it reaches everything: the tokens are
accepted by the same app backend the iOS client uses (there is no separate tvOS host — 
`tvos.bff.start.npox.nl` does not resolve), and behind it runs the playback chain this project
already mapped — player token, `stream-link`, CDN manifest, FairPlay licence. On an **Apple TV
HD running tvOS 26.6** the whole path ran to a 684-byte content key and picture and sound.

## Decision

**NPO light signs in with the OAuth device-code grant: a short code on the television,
approved at `id.npo.nl/koppel` on a phone, polled until tokens arrive.** No browser, no web
view, no `ASWebAuthenticationSession`, and the app never sees a password. The refresh token is
kept in the Keychain and renews the session silently.

The boundary from [ADR 0008](0008-one-boundary-around-the-npo-backend.md) is unchanged: this
decides what sits behind it, not its shape. The catalogue endpoints behind it are the app
backend's rather than the website's.

Two costs are part of the decision rather than footnotes to it:

- **We use NPO's own client identifier**, `npostart-app-tvos-prod`. It is a borrowed
  identifier, which is impersonation of the same kind as driving their login form would have
  been — done with the interface NPO built for televisions, and with the client that is
  correct for the platform we are building for.
- **The refresh token is single-use and rotates on every use**, so a token store cannot be
  shared between two installs. Seeding one client from another's store kills the first
  client's session at the next refresh.

## Alternatives considered

- **An in-app email and password form**, driving the website's NextAuth login with a cookie
  jar — the earlier plan, and the reason this ADR exists at all. Rejected: it types a password
  on a television and handles it in our process, it breaks if NPO adds a second factor, and
  the login page turns out to carry an AWS WAF challenge and to post an encrypted password
  field built by client-side JavaScript we would have to reimplement.
- **Authorisation code with PKCE through `ASWebAuthenticationSession`**, the flow NPO's iOS
  app uses. Not rejected on merit — it remains the right shape for iOS or macOS, and it is
  what a non-television client here would use. It is rejected *for tvOS*: it is unproven on
  the platform, untestable in the Simulator, and needs a callback scheme and a hand-off the
  device-code flow does without.
- **Register our own OAuth client with NPO** — the honest version, and not available: client
  registration is not open. Worth revisiting if NPO ever publishes an API.
- **Use the app backend's server-side progress** for continue-watching — deliberately not part
  of this decision. NPO light keeps watch state local and per mode (NFR-PRIV-01, FR-MODE-05);
  reading NPO's progress is a separate decision with a privacy consequence.

## Consequences

- **No password ever reaches this app.** FR-AUTH-02 and NFR-PRIV-02 hold honestly: the only
  stored credential is a refresh token, and the sign-in screen is a code and a wait rather
  than a keyboard.
- **The refresh token must live in the Keychain**, and this is a correctness requirement, not
  a preference. On a real Apple TV an app's `Documents` and `Application Support` are
  read-only — writing there fails with `NSCocoaErrorDomain 513` — and only `Caches` and `tmp`
  are writable, both evictable. A token in either is a session that silently ends. It goes in
  as `kSecClassGenericPassword` with `kSecAttrAccessibleAfterFirstUnlock`, so an unattended
  television can refresh after a reboot. The tvOS Simulator writes to Application Support
  happily, which is exactly why this had to be found on hardware.
- **Keychain items are not backed up and do not sync**: a factory reset means signing in
  again. That is acceptable for a television.
- **A coupled television stays signed in more or less indefinitely.** The device-code tokens
  carry no `sid` claim where the authorisation-code ones do, so there is no identity-provider
  session behind them: signing out in a browser or on a phone does not touch the television.
  The coupling ends when the refresh token expires, when NPO revokes the grant, or on an
  account-level action such as a password change. **How long that is, is not knowable from the
  token** — the access token is an hour, the refresh token is an opaque handle whose lifetime
  IdentityServer keeps server-side, and no `refresh_expires_in` is returned. Measuring it means
  holding one token untouched for weeks; until then FR-AUTH-07 is written to survive any answer.
- **Signing out is local only.** `/connect/revocation` advertises only `client_secret_basic`
  and `client_secret_post`, and this is a public client with no secret — the app cannot revoke
  its own token. Sign-out deletes the stored token; the grant lives on at the identity
  provider, and the app should say so and point at NPO's own linked-devices page.
- **Sign-in needs a second device**, which is a real cost for a household with no phone to
  hand, and it makes re-authentication the most expensive thing the app can ask for. That is
  what FR-AUTH-07 exists to avoid.
- **If NPO disables the grant for this client or invalidates the identifier**, the fallbacks in
  order are the authorisation-code flow above and, last, the password form — which is why both
  are recorded here rather than deleted.
