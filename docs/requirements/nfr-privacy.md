# Privacy and data handling

Prefix `NFR-PRIV`. What the family does in this app stays on this Apple TV,
except for how far something was played, which NPO is told.

## NFR-PRIV-01 — Local, except the position of what plays

- **Status:** Accepted

Pins, the watch later list, search history and the recently watched row are
stored on the device and are never sent anywhere — not to the NPO Plus
account, not to iCloud, not to a server of the app's own.

One thing is shared with the NPO account, deliberately: **where playback of a
programme is**, reported to NPO while it plays (FR-PLAY-12) and read back from
it (FR-PLAY-13, FR-HOME-12), together with taking a programme off NPO's list
of what to go on with (FR-HOME-13, FR-SET-05). It is what makes an episode
watched on the television watched in NPO's own apps, and it is all of it
([ADR 0028](../adr/0028-share-positions-with-npo-through-its-stream-events.md)).

**Acceptance criteria**

- No request body carries pins, the watch later list or search terms, beyond
  the search query needed to answer the search itself.
- Taking something off NPO's list names the programme and the profile, and
  nothing else.
- A report to NPO carries the account, the profile, the programme, the
  position and the programme's length, and what NPO's backend needs to accept
  it. It carries no page, no tile, no search and nothing that was not played.
- `UserDefaults` and the SwiftData store are local; no CloudKit container and
  no iCloud key-value store is configured.
- Signing in on another device does not carry any of this across.

## NFR-PRIV-02 — Credentials only in the Keychain

- **Status:** Accepted

Session tokens and credential material live in the Keychain and nowhere else
(FR-AUTH-02).

**Acceptance criteria**

- No token appears in `UserDefaults`, the SwiftData store, a file in the
  container, or a crash report.
- No token, password or authorisation header is logged, at any log level, in
  a release build.
- A debug build keeps them only when it was launched to keep whole requests
  and responses (NFR-DIAG-03), and then only in files on the device: never in
  the system log, which other tools read.

## NFR-PRIV-03 — No third-party analytics or tracking

- **Status:** Accepted

The app contains no analytics SDK, no crash reporter that ships user data off
the device, and no advertising identifier use.

**Acceptance criteria**

- The dependency list contains no analytics or advertising package.
- The app contacts only the hosts that serving NPO's own content requires:
  NPO's website and identity provider, its player and DRM services, and the
  content delivery network its streams are served from — plus Apple's own
  services. Some of those are run for NPO by third parties, which is why this
  is a list of purposes rather than a list of domains.
- The app contacts no advertising host, and does not follow the
  advertisement and tracking URLs NPO's own responses may contain
  (FR-AUTH-05).
- The one measurement host it contacts is NPO's own, because that is where
  NPO takes a playback position from, and only with the reports FR-PLAY-12
  describes: none of the page views, clicks and offers NPO's own app sends
  there.

## NFR-PRIV-04 — Erasing really erases

- **Status:** Implemented

When the user erases local data (FR-SET-04), it is gone.

**Acceptance criteria**

- After erasing, no pin, history entry, position or search term is readable
  from the store.
- Erased data does not reappear from a cache after relaunch.
