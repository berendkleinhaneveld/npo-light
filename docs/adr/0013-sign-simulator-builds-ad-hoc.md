# 0013. Sign simulator builds ad hoc, so the tests can reach the Keychain

- **Status:** Accepted
- **Accepted:** 2026-10-02
- **Date:** 2026-10-02
- **Deciders:** @berendkleinhaneveld

## Context

`scripts/build.sh` and `scripts/test.sh` — and therefore CI — built the app
for the simulator with `CODE_SIGNING_ALLOWED=NO`. The reasoning was sound when
it was written: a simulator does not need a signed binary to launch, and CI has
no signing identity to sign with.

The session lives in the Keychain, and on a television that is a correctness
requirement rather than a preference (FR-AUTH-02,
[ADR 0007](0007-sign-in-with-the-device-code-grant.md)).
[ADR 0009](0009-test-doubles-at-two-seams.md) keeps the Keychain out of every
other test with an in-memory store, and says in return that the real store
"needs its own integration tests".

Those tests cannot run in an unsigned app. A binary without a signature has no
application identifier, so it has no Keychain access group, and every
`SecItem` call answers `errSecMissingEntitlement` (`-34018`) — on save, on
load and on delete alike. The first run of `KeychainTokenStoreTests` under
`scripts/test.sh` failed exactly that way, three out of three, while the same
tests passed from a build signed with the ad-hoc identity.

The failure is in the pipeline and not in the store: Xcode itself signs a
simulator build "to run locally" by default, so the app has always had a
Keychain when run from Xcode and never when run from the scripts.

## Decision

**The scripts sign simulator builds with the ad-hoc identity**
(`CODE_SIGN_IDENTITY=-`), with manual signing style and an empty team and
provisioning profile, so that the build asks for no certificate, no account
and no profile. It is set in one place, `SIMULATOR_SIGNING` in
`scripts/common.sh`, which both scripts and CI already share.

Nothing changes for a device build or for a build from Xcode: the project
keeps automatic signing with the owner's team, and the scripts override it on
the command line only.

## Alternatives considered

- **Leave the Keychain store untested** — rejected. It is the one piece of the
  sign-in that ADR 0009's doubles deliberately do not cover, and a store that
  silently fails to save is a session that ends at the next launch.
- **Skip the Keychain tests when the Keychain is unavailable** — rejected. A
  test that passes by not running is the weakening AGENTS.md forbids, and CI is
  exactly where it would always be skipped.
- **Sign with a real development identity on CI** — rejected. It puts a
  certificate and its password in the repository's secrets to obtain what the
  ad-hoc identity gives for nothing.
- **A separate signed test run for the Keychain suite only** — rejected. Two
  build configurations to keep in step, and the app under test would still be
  the unsigned one everywhere else.

## Consequences

- `KeychainTokenStoreTests` run locally and on CI, against the simulator's real
  Keychain, each under a service name of its own run.
- The app the UI tests launch has a Keychain too, which the sign-in flow needs
  as soon as a UI test drives it.
- Builds take marginally longer: every product is signed.
- **This is evidence about the simulator only.** That the token survives a
  reboot, and is readable on a television nobody has touched, remain device
  checks (ADR 0009); a green suite says nothing about either.
- If ad-hoc signing ever stops being available without an identity on a CI
  runner, the fallback is the third alternative above, and this record gets a
  successor.
- Reversing it is restoring three lines in `scripts/common.sh` — and losing the
  Keychain tests with them.
