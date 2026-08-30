# Out of scope

Things the app deliberately does not do. Each is here so that nobody
re-litigates it in a pull request; changing one means adding requirements, and
probably an ADR.

## Not in this app at all

- **Live streams and channels.** No live television, no channel list, no
  "kijk nu" rail. The app is for on-demand items only.
- **Advertisements.** Sign-in is required precisely so the app never has to
  play, schedule or measure one (FR-AUTH-01, FR-AUTH-05).
- **Account sync.** Nothing about viewing is written back to the NPO Plus
  account, and nothing is read from it beyond what is needed to authenticate
  and to play (NFR-PRIV-01). Whether NPO even offers this is beside the point:
  the app does not use it.
- **Analytics and tracking** of any kind (NFR-PRIV-03).
- **Downloads and offline playback.** Caching covers metadata, not streams
  (FR-CONTENT-04).
- **Profiles beyond the two modes.** Normal and kids are modes, not accounts;
  there is no per-child profile, no avatar, no per-person history.
- **A companion iOS or iPadOS app.**

## Deferred, not rejected

- **A discover page.** Wanted eventually, and most likely as one more row on
  the home page rather than a separate page, so that the app stays effectively
  one screen. Not designed yet; no requirements written.
- **A PIN or other gate on the mode switch.** Deliberately absent
  (FR-MODE-02). If a child turns out to escape kids mode too easily, that is a
  new requirement, not a change to the existing one.
- **Manual ordering of pinned items.** Pinned order is chronological
  (FR-HOME-02). Drag-to-reorder can come later if the row gets long.
- **Recommendations, "because you watched", trending.** Deliberate viewing is
  the point of the app.
