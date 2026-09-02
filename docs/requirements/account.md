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

**Acceptance criteria**

- No credential material appears in the app's container outside the Keychain.
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

**Acceptance criteria**

- After sign-out the app is on the sign-in screen and no token remains in the
  Keychain.
- Pins, recently watched and search history survive sign-out and are there
  again after signing back in.
- Erasing local data is a separate, explicit action (FR-SET-04).

## FR-AUTH-05 — No advertisements

- **Status:** Accepted

The app requests the advertisement-free stream variant that the NPO Plus
subscription provides, and contains no advertisement playback or tracking code
of its own.

**Acceptance criteria**

- No pre-roll, mid-roll or post-roll is requested, scheduled or rendered.
- If the backend returns a stream that requires advertisement handling, the app
  reports it as an error rather than playing an advertisement.

## FR-AUTH-06 — The sign-in mechanism

- **Status:** Proposed — blocked by [Q-01](open-questions.md#q-01--how-does-npo-plus-sign-in-work-on-tvos)

Whether sign-in is an on-device form, a device-code pairing flow, or something
else, is decided by a feasibility spike against NPO's actual endpoints. The
requirement above (FR-AUTH-01 to FR-AUTH-05) holds whichever mechanism wins;
this entry is where the chosen mechanism gets written down, with an ADR.

**Acceptance criteria**

- The spike records what NPO's backend supports in an ADR.
- This requirement is rewritten as the concrete flow and moved to `Accepted`.
