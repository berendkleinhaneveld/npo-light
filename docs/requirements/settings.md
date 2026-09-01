# Settings

A short screen, reachable only from normal mode (FR-MODE-06). Prefix `FR-SET`.

## FR-SET-01 — Settings is a normal-mode screen

- **Status:** Accepted

Settings is reachable from the normal-mode home page, and holds only the
handful of things below.

**Acceptance criteria**

- Reachable from normal-mode home; unreachable from every kids-mode screen.
- Leaving settings returns to home with changes already applied.

## FR-SET-02 — The timings are configurable

- **Status:** Accepted

Three durations can be changed, with these defaults:

| Setting | Default | Requirement |
| --- | --- | --- |
| Pause between episodes in kids mode | 5 seconds | FR-PLAY-06 |
| Still-watching prompt in kids mode | 1 hour | FR-PLAY-08 |
| Still-watching prompt in normal mode | 3 hours | FR-PLAY-08 |

**Acceptance criteria**

- A fresh install uses exactly those defaults.
- Each setting is offered as a small set of sensible choices, not free text
  typed with a remote.
- A changed value takes effect without relaunching.
- Values persist across launches, and an unreadable stored value falls back to
  the default rather than crashing.

## FR-SET-03 — Sign out

- **Status:** Accepted

Settings offers sign-out (FR-AUTH-04).

**Acceptance criteria**

- Sign-out asks for confirmation.
- After confirming, the app is on the sign-in screen with no session stored.

## FR-SET-04 — Erase local data

- **Status:** Superseded by FR-SET-05

Named the four things erasing removes. Watch later adds a fifth
([watch-later.md](watch-later.md), FR-LATER-01), and a list of local data that
misses one is a promise the app does not keep (NFR-PRIV-04), so the requirement
was retired rather than rewritten.

## FR-SET-05 — Erase local data

- **Status:** Accepted

Settings can erase locally stored data: pins, recently watched, playback
positions, search history and the watch later list — for one mode or for both.

Supersedes FR-SET-04, which listed the same data without watch later.

**Acceptance criteria**

- Erasing asks for confirmation and names what will be removed, watch later
  included.
- Erasing one mode leaves the other mode's data untouched (FR-MODE-05,
  FR-LATER-10).
- After erasing, the affected home page shows its empty states (FR-HOME-09) and
  its watch later row is gone (FR-LATER-05).
- Erasing does not sign the user out.
