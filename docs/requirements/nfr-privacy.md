# Privacy and data handling

Prefix `NFR-PRIV`. Everything the family does in this app stays on this Apple
TV.

## NFR-PRIV-01 — Local only, no sync

- **Status:** Accepted

Pins, recently watched, playback positions and search history are stored on the
device and are never sent anywhere — not to the NPO Plus account, not to
iCloud, not to a server of the app's own.

**Acceptance criteria**

- No request body carries watch history, pins or search terms, beyond the
  search query needed to answer the search itself.
- The SwiftData store is local; no CloudKit container is configured.
- Signing in on another device does not carry any of this across.

## NFR-PRIV-02 — Credentials only in the Keychain

- **Status:** Accepted

Session tokens and credential material live in the Keychain and nowhere else
(FR-AUTH-02).

**Acceptance criteria**

- No token appears in `UserDefaults`, the SwiftData store, a file in the
  container, or a crash report.
- No token, password or authorisation header is logged, at any log level, in
  debug or release.

## NFR-PRIV-03 — No third-party analytics or tracking

- **Status:** Accepted

The app contains no analytics SDK, no crash reporter that ships user data off
the device, and no advertising identifier use.

**Acceptance criteria**

- The dependency list contains no analytics or advertising package.
- The only hosts the app contacts are NPO's own, plus Apple's own services.

## NFR-PRIV-04 — Erasing really erases

- **Status:** Accepted

When the user erases local data (FR-SET-05), it is gone.

**Acceptance criteria**

- After erasing, no pin, history entry, position or search term is readable
  from the store.
- Erased data does not reappear from a cache after relaunch.
