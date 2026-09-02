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
- The app contacts only the hosts that serving NPO's own content requires:
  NPO's website and identity provider, its player and DRM services, and the
  content delivery network its streams are served from — plus Apple's own
  services. Some of those are run for NPO by third parties, which is why this
  is a list of purposes rather than a list of domains.
- The app contacts no advertising or measurement host, and does not follow the
  advertisement and tracking URLs NPO's own responses may contain
  (FR-AUTH-05).

## NFR-PRIV-04 — Erasing really erases

- **Status:** Accepted

When the user erases local data (FR-SET-04), it is gone.

**Acceptance criteria**

- After erasing, no pin, history entry, position or search term is readable
  from the store.
- Erased data does not reappear from a cache after relaunch.
