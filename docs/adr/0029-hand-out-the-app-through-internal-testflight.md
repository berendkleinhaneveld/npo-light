# 0029. Hand out the app through internal TestFlight, uploaded from CI

- **Status:** Proposed
- **Date:** 2026-10-24
- **Deciders:** @berendkleinhaneveld

## Context

The app runs on the owner's Apple TV, installed from Xcode. A friend, with an
Apple TV of their own and no developer account, should be able to use it too,
and keep it working without a Mac being brought to the television.

Apple offers four ways to put an app on somebody else's Apple TV:

- **The App Store**, listed or unlisted, and **external TestFlight testers**.
  Both pass App Review. This app signs in with NPO's own client identifier
  ([ADR 0007](0007-sign-in-with-the-device-code-grant.md)) and is built on NPO's
  catalogue and brand; review is unlikely to accept that, and asking invites
  the question.
- **Internal TestFlight testers**: up to a hundred people who are users of the
  owner's App Store Connect team. Builds reach them without review, through the
  TestFlight app on the television, and expire after ninety days.
- **A development or ad hoc profile**: the television's identifier registered
  in the developer account, and the app installed from a Mac paired with it —
  on the friend's sofa, and again when the profile lapses.

The owner has a paid developer account. CI already runs on `macos-26` runners
with the Xcode the app needs, and signs nothing but simulator builds, ad hoc
([ADR 0013](0013-sign-simulator-builds-ad-hoc.md)).

## Decision

**We hand the app out through internal TestFlight only, and CI uploads it.**

- Each person who should have the app is a user of the App Store Connect team,
  with the least role that can test (Marketing, limited to this app), in an
  internal TestFlight group.
- `scripts/upload-testflight.sh` archives the Release configuration unsigned,
  with warnings as errors, then exports and uploads it in one step. The export
  signs it with Apple's **cloud-managed distribution certificate**, so no
  certificate or private key is stored anywhere. Every build is marked
  `testFlightInternalTestingOnly`, so none of them can be sent to external
  testers or to review by mistake.
- The build number is the upload's UTC time (`YYYYMMDDhhmm`): it rises with
  every upload, wherever it was made from, without a commit to bump it.
- `.github/workflows/testflight.yml` runs the script on `master`, when started
  by hand and on the first of every month, so that the newest build is never
  near its ninety days. It authenticates with an App Store Connect API key
  (Admin role, which cloud signing needs) kept in three repository secrets:
  `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8`. It never runs on a pull
  request.
- The app declares `ITSAppUsesNonExemptEncryption = NO`: its only encryption is
  the system's HTTPS, Keychain and FairPlay, which are exempt, and the
  declaration stops every upload from waiting on the export compliance
  question.

## Alternatives considered

- **The App Store, or external TestFlight** — rejected: both pass review, for
  the reasons above.
- **Ad hoc or development installs** — rejected: they need a Mac paired with
  every television, and someone to bring it.
- **Upload from the owner's Mac only** — kept as a fallback, not chosen: the
  script runs there too, with the account signed in to Xcode, but a monthly
  upload that depends on somebody remembering it is a television that stops
  working in the fourth month.
- **A distribution certificate and profile in the repository's secrets**,
  installed into a temporary keychain on the runner — rejected: a private key
  and its password to rotate and guard, for what cloud signing gives for an
  API key.
- **fastlane** — rejected: a Ruby toolchain and a dependency for two
  `xcodebuild` calls.

## Consequences

- A friend needs an Apple ID, the TestFlight app and an NPO Plus account of
  their own — never a shared session, which ADR 0007's rotating refresh token
  would end at the next refresh.
- The repository's secrets now hold a key that can manage the owner's App
  Store Connect team. It reaches only the upload job, which runs code from
  `master` alone. Revoking it in App Store Connect stops the uploads and
  nothing else.
- This is the first CI job to sign for a device. ADR 0013 still holds for the
  tests: they keep the ad hoc identity and never see the key.
- Release builds are now compiled, by this job and only by it. A warning that
  appears only in Release fails the upload, as Rule 2 asks, and shows up later
  than one in Debug would.
- GitHub disables a scheduled workflow in a public repository after sixty days
  without activity. If that happens, the builds lapse thirty days later; the
  remedy is to re-enable the workflow and start it by hand.
- **The unsigned archive is the least proven part.** If the export ever stops
  signing an unsigned archive, the fallback is to archive with automatic
  signing and the same key, which lets Xcode create a development certificate
  on each run; that change gets a successor to this record.
- Reversing it is deleting the workflow and the script, and revoking the key.
