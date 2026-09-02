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
- **A watch later list that holds series.** A series is followed, so it is
  pinned (FR-HOME-03); watch later holds one playable thing at a time
  (FR-LATER-02). Wanting both for the same series means pinning it and saving
  the one episode.
- **A watch later list that survives being watched.** Finishing a saved item
  takes it off the list (FR-LATER-07). There is no "watched, but keep it" flag
  and no archive of what was once saved.

## Deferred, not rejected

- **A discover page.** Wanted eventually, and most likely as one more row on
  the home page rather than a separate page, so that the app stays effectively
  one screen. Not designed yet; no requirements written.
- **A PIN or other gate on the mode switch.** Deliberately absent
  (FR-MODE-02). If a child turns out to escape kids mode too easily, that is a
  new requirement, not a change to the existing one.
- **Manual ordering of pinned or saved items.** Both rows are chronological,
  newest first (FR-HOME-02, FR-LATER-04). Drag-to-reorder can come later if a
  row gets long — the uncapped watch later list (FR-LATER-06) is the likelier
  of the two to need it.
- **Recommendations, "because you watched", trending.** Deliberate viewing is
  the point of the app.
