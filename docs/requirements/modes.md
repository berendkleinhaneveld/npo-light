# Normal mode and kids mode

The app is always in exactly one mode. Prefix `FR-MODE`.

## FR-MODE-01 — Two modes, remembered across launches

- **Status:** Accepted

The app has a normal mode and a kids mode. It launches in whichever mode it was
in when it was last used.

**Acceptance criteria**

- A fresh install starts in normal mode.
- Switching to kids mode and relaunching starts in kids mode.
- The stored mode survives sign-out and sign-in (FR-AUTH-04).

## FR-MODE-02 — Switching is one action and is not gated

- **Status:** Accepted

Switching modes is a single, always-visible action on the home page. It asks
for no PIN, password or confirmation in either direction.

Kids mode needs an NPO kids profile on the account to browse as (FR-MODE-04).
An account without one has no kids mode to switch to, and the home page says so
in place of the switch rather than offering one that fails.

**Rationale.** This is a family device, not a kiosk. The owner chose
convenience over enforcement; if that changes, it becomes a new requirement,
not a change to this one.

**Acceptance criteria**

- The switch is reachable from the home page in one remote action, in both
  modes.
- Switching takes effect immediately: the home page reloads with the other
  mode's pins and history.
- The switch is not offered during playback.
- On an account without an NPO kids profile, the place of the switch explains
  that kids mode needs a kids profile and that one is made in NPO's own app or
  on npo.nl. The app does not create one itself.
- A kids profile made after signing in is found without signing in again.

## FR-MODE-03 — The current mode is unmistakable

- **Status:** Accepted

A glance at the screen tells you which mode you are in — kids mode has its own
visual identity, not just a different content list.

**Acceptance criteria**

- Kids mode and normal mode differ in a way that does not rely on colour alone
  (NFR-A11Y-04).
- The distinction is present on every screen the mode affects, not only the
  home page.

## FR-MODE-04 — Kids mode browses the youth catalogue

- **Status:** Accepted

In kids mode, every item the app offers — home page, search results, next
episodes — comes from NPO's youth catalogue. Browsing within that catalogue is
unrestricted; no per-item parental curation is needed.

**How.** The youth catalogue is NPO's own, and NPO applies it: kids mode browses
as the account's NPO kids profile, and normal mode as its general profile
([Q-03](open-questions.md#q-03--how-is-the-youth-catalogue-identified),
[ADR 0014](../adr/0014-each-mode-browses-as-an-npo-profile.md)). The app does
no filtering of its own, because the rule NPO applies — a whole series is in or
out — cannot be rebuilt from the ratings on single items.

**Acceptance criteria**

- A search in kids mode never returns an item outside the youth catalogue
  (FR-SEARCH-08).
- An item pinned in normal mode is not shown in kids mode (FR-MODE-05 makes
  this automatic).
- Every catalogue request in kids mode is made as the account's NPO kids
  profile; none is made as the general profile and filtered afterwards.
- Without a kids profile on the account, kids mode is unavailable (FR-MODE-02),
  and a stored kids mode (FR-MODE-01) falls back to normal mode rather than
  showing the general catalogue under a kids-mode heading.
- With more than one kids profile on the account, the first one NPO lists is
  used.

## FR-MODE-05 — Each mode has its own pins, history and search history

- **Status:** Accepted

Pinned items, recently watched and search history are stored per mode. Nothing
a child watches appears on the adult home page, and the other way round.

**Acceptance criteria**

- Pinning in one mode does not add the item to the other mode's pinned list.
- Playing an item in one mode does not add it to the other mode's recently
  watched list.
- A search term entered in one mode does not appear in the other mode's recent
  searches.
- Playback positions are per mode as well: the same episode may be at different
  positions in the two modes.

## FR-MODE-06 — Settings are a normal-mode screen

- **Status:** Accepted

Settings (FR-SET) are reachable only from normal mode. Kids mode offers no
entry point to them.

**Rationale.** With no PIN gate (FR-MODE-02), keeping settings out of kids mode
is the one thing that stops a child from changing the still-watching timer or
signing the household out by accident.

**Acceptance criteria**

- No path from any kids-mode screen reaches settings.
- Switching to normal mode and opening settings works as normal.
