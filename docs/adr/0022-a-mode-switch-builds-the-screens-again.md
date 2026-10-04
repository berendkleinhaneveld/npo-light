# 0022. A mode switch builds the screens again

- **Status:** Proposed
- **Date:** 2026-10-04
- **Deciders:** @berendkleinhaneveld

## Context

Every store and every catalogue call takes the mode as an argument
([ADR 0011](0011-four-layers-above-the-npo-boundary.md),
[ADR 0012](0012-what-the-local-store-holds.md)), and every screen model is
made for one mode and keeps it. Until now that mode was always normal.
FR-MODE-02 asks for a switch on the home page that takes effect at once, and
FR-MODE-05 that nothing of one mode shows in the other.

## Decision

**The mode is one observable value, and the signed-in screens are made for
it.** `ModeModel` holds the current mode and whether the account has an NPO
kids profile ([ADR 0014](0014-each-mode-browses-as-an-npo-profile.md)). The
root view gives the home page the mode as its identity: when the mode changes
SwiftUI discards the home page, the navigation stack on it and their models,
and makes them again from the composition root's factories, for the new mode.
No model changes its mode.

**The mode is kept in `UserDefaults`**, one value beside the lists and outside
their ceiling, as ADR 0012 said. It is read once at launch and written at
every switch. Signing out does not touch it (FR-MODE-01).

**Whether there is a kids profile is asked when the home page appears**, not
once at sign-in, so that one made a minute ago is found. Until NPO has
answered there is neither a switch nor an explanation; a stored kids mode on
an account without a kids profile is replaced by normal mode, and that is
written down (FR-MODE-04).

**Kids mode is marked on every page of the stack** by a badge with a symbol
and the word, laid over the stack rather than drawn by each page
(FR-MODE-03).

## Alternatives considered

- **Models with a mode that can change** — one set of models for the life of
  the app. Rejected: every model would need a "start over" that clears
  exactly what it shows, and one that forgets a field shows a child the
  adults' row.
- **A store container per mode** — ADR 0012 rejected it, and nothing here
  reopens that.
- **Asking for the profiles at sign-in only** — one request fewer per visit
  to the home page. Rejected by FR-MODE-02's last criterion.

## Consequences

- A switch throws away where the user was: the stack, the search text, the
  scroll position. It is made from the home page, where there is little of
  that.
- A mode leak needs a model to be handed the wrong mode at the composition
  root, which is one place to read.
- The player is not part of the stack and does not show the badge; the switch
  is not offered while it plays.
- Settings have no way in from kids mode (FR-MODE-06): the home page of
  kids mode does not draw it, and its model does not open it.
- A launch by a test keeps its mode in memory, so that a test cannot leave
  the simulator in kids mode.
