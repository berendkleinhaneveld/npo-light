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
| `profiles-200.json` | `GET ios.bff.start.npox.nl/profiles`, an account with a general and a kids profile | 2026-09-03 |
| `search-200.json` | `GET ios.bff.start.npox.nl/search?query=fr&page=1`, as the general profile; two items kept per collection | 2026-09-03 |
| `search-single-programme-200.json` | `GET ios.bff.start.npox.nl/search?query=subst&page=1`, as the general profile: one series, two of its eight episodes, and a film. From the app's own request log on an Apple TV | 2026-10-04 |
| `series-page-200.json` | `GET ios.bff.start.npox.nl/series/page/{guid}`, as the kids profile | 2026-09-03 |
| `season-programs-200.json` | `GET ios.bff.start.npox.nl/series/seasons/{guid}/programs?sort=asc`, as the kids profile; three episodes kept | 2026-09-03 |
| `player-200.json` | `GET ios.bff.start.npox.nl/programs/player/{guid}?player-environment=production` | 2026-08-31 |
| `stream-link-200.json` | `POST prod.npoplayer.nl/stream-link`, for a Plus account; the manifest address and both tokens are placeholders | 2026-08-31 |
| `stream-link-signed-address-200.json` | `POST prod.npoplayer.nl/stream-link`, for a Plus account and an older children's programme: no credential header, the authorisation is in the licence address; the manifest address and the `auth` and `sig` values are placeholders. From the app's own request log on an Apple TV | 2026-10-04 |
| `home-200.json` | `GET ios.bff.start.npox.nl/pages/by/slug/home`, as the general profile: the row NPO's app goes on from, with an episode and a film that each have a position, and one of the nineteen rows that are not read. From a capture of NPO's iPhone app | 2026-10-06 |
| `season-programs-progress-200.json` | `GET ios.bff.start.npox.nl/series/seasons/{guid}/programs?sort=asc`, as the general profile, half a minute into the first episode; two episodes kept. Same capture | 2026-10-06 |
| `player-progress-200.json` | `GET ios.bff.start.npox.nl/programs/player/{guid}?player-environment=production` for a programme the profile has a position for. Same capture | 2026-10-06 |

## The rules

**Sanitised.** No real tokens, account identifiers, subscription identifiers or
personal data. Every credential value here is a placeholder, and the GUIDs are
sequential rather than real. The one exception is the `user_code` in
`device-authorization-200.json`, which is the eight-digit code from the recon
run: it is one-time, it lapsed five minutes after it was issued, and keeping it
matches the note it came from.

**A position is left as it is too.** The three fixtures of 2026-10-06 carry how
far the capturing account had watched something: that is the field they are
there for, and the pair of numbers has to stay a pair — the length NPO measured
against is only found by dividing one by the other.

**Catalogue data is left as it is.** Titles, synopses, image addresses and the
identifiers of series and episodes are NPO's public catalogue, not anything
about an account, so the catalogue fixtures keep them. The profiles fixture is
the exception among the newer ones: its identifiers and names are placeholders.

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
