# Accessibility and remote navigation

Prefix `NFR-A11Y`. A tvOS app is used from three metres away, with a remote
that has five directions and no pointer.

## NFR-A11Y-01 — Everything is reachable with the remote

- **Status:** Accepted

Every action in the app can be performed with the Siri Remote's directional
pad and its buttons.

**Acceptance criteria**

- No action exists only as a gesture that is not discoverable — where a long
  press or the play/pause button is used (unpin, delete a search term), the
  same action is also reachable from a detail page or a menu.
- Focus never gets stuck: from any focused element, there is a way back to the
  page's main navigation.
- Focus never disappears: after a list changes — an item removed, a row
  refreshed — focus lands on a defined neighbour, not nowhere
  (FR-HOME-10).
- The Menu button always goes one level back, and from the home page it leaves
  the app.

## NFR-A11Y-02 — VoiceOver can drive the app

- **Status:** Accepted

Every focusable element has a meaningful VoiceOver label.

**Acceptance criteria**

- A tile reads its title and its kind — series, film, episode — not the name of
  an image asset.
- Progress on a recently watched tile is announced, not conveyed only by a bar.
- Buttons whose label is an icon carry an accessibility label.
- A countdown before the next episode (FR-PLAY-06) is announced.

## NFR-A11Y-03 — System text and motion settings are respected

- **Status:** Accepted

The app follows the accessibility settings tvOS offers.

**Acceptance criteria**

- Text scales with the system text size without truncating a title to
  meaninglessness or breaking a row's layout.
- Bold text and increased contrast settings are honoured.
- Reduce Motion removes decorative animation, including the focus parallax on
  tiles where it is decorative.

## NFR-A11Y-04 — Never colour alone

- **Status:** Accepted

No state is communicated by colour alone, and focus is always visible.

**Acceptance criteria**

- The current mode is distinguishable without colour (FR-MODE-03).
- Watched, partly watched and unwatched are distinguishable without colour.
- The focused element is unambiguous at three metres, on a bright and a dark
  television.
- Text meets a contrast ratio of at least 4.5:1 against its background.

## NFR-A11Y-05 — Dutch is the language of the interface

- **Status:** Proposed — blocked by [Q-05](open-questions.md#q-05--what-language-is-the-interface-in)

The content is Dutch and the audience is a Dutch family, so the interface is
expected to be Dutch, with strings localised rather than hard-coded.

**Acceptance criteria**

- User-facing strings come from a string catalogue, never from a literal in a
  view.
- Adding a second language requires no code change.
