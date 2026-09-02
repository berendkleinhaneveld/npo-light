# Fixtures

Captured response bodies, used to test the decoding inside the NPO boundary
against shapes the real hosts actually returned (ADR 0009).

They are **snapshots of an unversioned API, not a contract**. Nothing in CI
talks to NPO, so they will go stale silently. A fixture that records its
capture date is still better evidence than an invented one.

## Where they came from

All of it out of the notes for the proof-of-concept that proved the sign-in and
the playback chain — a spike built outside this repository and deliberately kept
there, because it holds capture material from a private account (ADR 0008). What
is here is extracted and rewritten, not copied.

| File | Endpoint | Captured |
| --- | --- | --- |
| `device-authorization-200.json` | `POST id.npo.nl/connect/deviceauthorization` | 2026-09-01 |
| `token-authorization-pending-400.json` | `POST id.npo.nl/connect/token`, poll before approval | 2026-09-01 |
| `token-success-200.json` | `POST id.npo.nl/connect/token`, poll after approval | 2026-09-01 |
| `account-premium-200.json` | `GET ios.bff.start.npox.nl/account` | 2026-09-01 |

## The rules

**Sanitised.** No real tokens, account identifiers, subscription identifiers or
personal data. Every credential value here is a placeholder, and the GUIDs are
sequential rather than real. The one exception is the `user_code` in
`device-authorization-200.json`, which is the eight-digit code from the recon
run: it is one-time, it lapsed five minutes after it was issued, and keeping it
matches the note it came from.

**Minimised, but shape-preserving.** Fields the app never reads are dropped;
the nesting, the names and the types are left exactly as they came. The point is
to catch a decoder that assumed something the real response does not promise.

**Only what was observed.** `token-success-200.json` carries the four fields the
recon notes record — `access_token`, `id_token`, `refresh_token`, `expires_in`.
IdentityServer conventionally returns `token_type` and `scope` as well, but
neither was written down, so neither is here. A decoder that needs them is a
decoder relying on something nobody checked.

**No fixture for a shape nobody has captured.** The clearest case is an account
*without* NPO Plus. Every capture and every prototype run used a premium
account, and `Q-08` was answered by decision rather than by evidence: anything
other than exactly `premium` is treated as free. An `account-free.json` would
therefore be fabricated data wearing the costume of a capture. Tests for that
path build the body inline, where it is visible that the value is invented.

## Adding one

Extract it from the spike's notes, sanitise it, trim it, add the row above with
the date it was captured, and say in the pull request which run it came from. If it is a
shape that was reasoned about rather than seen, it does not belong here.
