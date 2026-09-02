# Account and sign-in

The app is an NPO Plus client. Prefix `FR-AUTH`.

## FR-AUTH-01 — Sign-in is required

- **Status:** Accepted

The app requires an NPO Plus account. Until a session exists, the only screen
is the sign-in screen; there is no browsing, searching or playback without one.

**Rationale.** A signed-in NPO Plus session is what makes the streams
advertisement-free (FR-AUTH-05). Supporting a signed-out, ad-supported mode
would mean building the advertisement handling this app exists to avoid.

**Acceptance criteria**

- Launching without a stored session shows sign-in and nothing else.
- Launching with a valid stored session goes straight to the home page.
- Sign-in state survives relaunch.

## FR-AUTH-02 — Credentials live in the Keychain

- **Status:** Accepted

Tokens and any credential material are stored in the Keychain, never in
`UserDefaults`, the SwiftData store, a plist or a log line (NFR-PRIV-02).

**Rationale.** On a television this is a correctness requirement before it is a
privacy one. A real Apple TV gives an app no writable durable storage at all —
`Documents` and `Application Support` are read-only there, and the only
writable directories are evictable caches — so the Keychain is not the *safest*
place for the token, it is the *only* place it survives. The tvOS Simulator
writes to those directories happily, which is why this has to be stated rather
than discovered.

**Acceptance criteria**

- No credential material appears in the app's container outside the Keychain.
- The stored token survives relaunch and a reboot of the television, without
  the user signing in again.
- The token is readable after a reboot on a television nobody has interacted
  with, so a scheduled refresh does not depend on someone being in the room.
- No credential material appears in log output at any log level.
- Erasing local data (FR-SET-04) does not leave orphaned Keychain items behind
  after sign-out.

## FR-AUTH-03 — Sessions refresh silently

- **Status:** Accepted

An expired session is refreshed without the user noticing. Only a refresh that
genuinely fails sends the user back to sign-in.

**Acceptance criteria**

- A request that fails because the session expired is retried once after a
  successful refresh.
- Concurrent requests hitting an expired session trigger exactly one refresh.
- A failed refresh returns to the sign-in screen; pins, history and search
  history are kept, so signing back in restores the same home page.

## FR-AUTH-04 — Sign out

- **Status:** Accepted

The user can sign out from settings (FR-SET-03). Signing out clears the session
but keeps local data.

**Sign-out is local, and the screen says so.** The app cannot revoke its own
token at NPO — revocation is closed to a client without a secret, and this is a
public client ([ADR 0007](../adr/0007-sign-in-with-the-device-code-grant.md)).
Signing out therefore forgets the token here; the coupling continues to exist
at NPO until it expires or is removed there. An app that implied otherwise
would be lying about a privacy-relevant action, which NFR-PRIV-02 does not
allow.

**Acceptance criteria**

- After sign-out the app is on the sign-in screen and no token remains in the
  Keychain.
- Signing out tells the user that the television is forgotten here but remains
  linked to their NPO account, and where to remove it there.
- Pins, recently watched and search history survive sign-out and are there
  again after signing back in.
- Erasing local data is a separate, explicit action (FR-SET-04).

## FR-AUTH-05 — No advertisements

- **Status:** Accepted

The app requests the advertisement-free stream variant that the NPO Plus
subscription provides, and contains no advertisement playback or tracking code
of its own.

**This is held structurally, not by vigilance.** Every account the app will
serve has NPO Plus, because an account without it is signed out before it
reaches the catalogue (FR-AUTH-08). So the app is never in the state where NPO
would supply an advertisement in the first place, and the criteria below are
the second line rather than the first.

**Acceptance criteria**

- No pre-roll, mid-roll or post-roll is requested, scheduled or rendered.
- If the backend returns a stream that requires advertisement handling, the app
  reports it as an error rather than playing an advertisement.
- The advertisement fields NPO's stream response carries are ignored, not
  followed. For a signed-in Plus account they are empty in any case: the
  response says there is no pre-roll, where the same programme requested
  anonymously carries one.

## FR-AUTH-06 — Sign-in is a code on the screen, approved on a phone

- **Status:** Accepted

The television displays a short code, a web address, and a QR code. The user
either scans the QR code with a phone, or types the address and enters the
code by hand; they sign in to NPO there and approve, and the television
notices by itself and continues. The app never draws a password field and
never handles a password.

**Rationale.** This is how NPO's own television app signs in, and it is the
only flow proven to work on this platform: it was run end to end on an Apple
TV, through to protected content playing
([Q-01](open-questions.md#q-01--how-does-npo-plus-sign-in-work-on-tvos),
[ADR 0007](../adr/0007-sign-in-with-the-device-code-grant.md)). It also needs
nothing from tvOS that tvOS is willing to give: no web view, no browser
hand-off, only a label and a poll. Typing a password with a remote control is
avoided entirely, and so is the app ever holding one.

**Why a QR code.** The sign-in response carries two addresses: a short one for
a person to read and type, and a complete one with the code already in its
query string. The second exists to be scanned, and scanning removes the only
tedious step left — copying an eight-digit code onto a phone, across a room,
correctly, inside five minutes. It is an accelerator and never the only route:
everything still works from the printed address and code alone, which is what
keeps the screen usable for someone with no camera to hand, sitting too far
away, or listening to it through VoiceOver (NFR-A11Y-02).

**Acceptance criteria**

- Starting sign-in shows the code and the address on the television, both
  large enough to read from a sofa, and the app renders no credential fields
  of its own.
- The address shown as text is the **short** one, without the code embedded in
  it, so that it stays short enough to type.
- A QR code is shown beside them, encoding the **complete** address — the one
  that carries the code in its query string — so that scanning it lands on the
  approval page with nothing left to enter.
- The QR code encodes the complete address **exactly as the sign-in response
  gives it**, rather than one the app builds by appending the code to the short
  address itself.
- Sign-in can be completed from the code and the address alone, with the QR
  code ignored or unscannable; nothing is reachable only by scanning
  (NFR-A11Y-01, NFR-A11Y-02).
- The QR code is generated on the device. No image is fetched, and the code is
  not sent to any host to render it (NFR-PRIV-03).
- The QR code is scannable from normal viewing distance: large enough, with its
  quiet zone intact, and drawn at a fixed dark-on-light contrast that does not
  follow the interface's own light or dark styling (NFR-A11Y-04).
- A refreshed code refreshes the QR code with it, so what is on screen and what
  the app is polling for are never different codes.
- The screen states plainly what the user has to do on the other device, and
  keeps waiting without any further input on the television.
- Approving on the other device continues by itself, with no "I'm done" button
  to press on the television, and lands on the home page (FR-AUTH-01).
- The app stores only the tokens it receives, in the Keychain (FR-AUTH-02,
  NFR-PRIV-02), and never receives a password at all.
- A code that expires before it is approved says so and offers a fresh one
  rather than failing silently or waiting forever.
- A sign-in the user abandons, and one that fails on the network, are
  distinguishable on screen, and each offers a way to try again.
- An account without an NPO Plus subscription signs in successfully and is
  then turned away by the subscription check, with its own explanation
  (FR-AUTH-08) — the sign-in itself does not fail, and does not report a
  password or network problem.

## FR-AUTH-07 — The session is kept alive without asking again

- **Status:** Accepted

The stored session carries an expiry. The app refreshes it before it lapses and
after it has lapsed, without involving the user, and sends the user back to
sign-in only when NPO itself no longer recognises the session.

**Rationale.** Signing in needs a second device (FR-AUTH-06), so asking for it
again is the most expensive thing the app can do — and a television is the
device most likely to be picked up after a fortnight of not being touched. The
access token lasts an hour and comes with a refresh token, so renewing is a
real mechanism rather than a re-run of a login.

**How long a coupled television stays signed in is not known**, and the
requirement is written so that it does not depend on the answer: the token
carries no session identifier, so nothing outside the app ends it, and its life
is the refresh token's life — a server-side value NPO does not return. It ends
when that expires, when NPO revokes the grant, or on an account-level change
such as a new password.

**Acceptance criteria**

- The app knows when the access token expires without having to make a request
  fail first, and renews it before it does.
- A refresh that NPO accepts is invisible: no screen, no interruption to
  playback (FR-PLAY-10).
- Concurrent requests meeting an expired token cause exactly one refresh
  (FR-AUTH-03).
- **Each refresh replaces the stored token before it is used again.** NPO's
  refresh tokens are single-use and rotate, so a refresh that succeeds while
  the old token is still stored leaves the session dead on the next attempt.
- An interrupted refresh — the app quits, or the network drops, between asking
  and storing — leaves the app able to recover rather than stranded with a
  spent token.
- A refresh NPO rejects returns to sign-in with local data intact.
- The refresh token is the only credential kept, and it is kept in the Keychain
  (FR-AUTH-02).

## FR-AUTH-08 — NPO Plus is required, and the app says so plainly

- **Status:** Accepted — the exact check awaits
  [Q-08](open-questions.md#q-08--what-does-an-account-without-npo-plus-look-like)

Immediately after signing in, the app checks that the account has an NPO Plus
subscription. If it does not, the app explains that NPO light needs one, that
this account does not have it, and that it is signing the account out again —
and then signs out.

**Rationale.** This app never shows advertisements (FR-AUTH-05), and the
cleanest way to keep that promise is to never be in the situation where NPO
would supply one. A signed-in Plus account is served streams with the
advertisement fields empty; the same programme fetched anonymously carries a
pre-roll. What a signed-in account *without* Plus is served has not been
established, and the honest options are to find out and handle it, or to
decline the case. This requirement declines it: NPO light is a better way to
watch a subscription the household already pays for, not a way to watch NPO
for free.

Turning the account away costs little, because it is a state the user can do
something about — and it is far better than the alternative of a signed-in app
whose every tile says the item cannot be played.

**Acceptance criteria**

- The subscription is checked as part of completing sign-in, before the home
  page is shown, so an account without Plus never reaches the catalogue.
- An account with Plus proceeds to the home page with nothing shown and nothing
  to dismiss (FR-AUTH-01).
- An account without Plus is told three things in plain Dutch: that NPO light
  requires NPO Plus, that this account does not have it, and that it is being
  signed out.
- The message stays until the user acknowledges it. Sign-out follows the
  acknowledgement rather than racing it, so the explanation cannot be missed.
- Signing out this way is an ordinary sign-out (FR-AUTH-04): the token is
  removed from the Keychain, and local data is kept.
- Signing in again with the same account gives the same explanation again,
  rather than a different error or a loop that hides the reason.
- A subscription check that fails because the network failed is reported as a
  network problem with a retry, and does **not** sign the account out — an
  unreachable backend is not evidence that the account lacks a subscription.
- The check is repeated whenever the account is refreshed, not only at sign-in,
  so a subscription that lapses while the app is signed in is caught rather
  than quietly reintroducing advertisements.
