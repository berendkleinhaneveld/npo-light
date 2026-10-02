# Interactive wireframe

A clickable sketch of NPO light in a browser, drawn from the requirements in
[`docs/requirements/`](../docs/requirements/README.md). It is published to
GitHub Pages from `master` by `.github/workflows/wireframe.yml`; why it exists
and what it is not are in
[ADR 0010](../docs/adr/0010-publish-an-interactive-wireframe.md).

**The requirements win.** Where this sketch and a requirement disagree, the
sketch is wrong. Anything it settles that no requirement does is a proposal
(see the list below), not a specification.

## Running it locally

```sh
./scripts/build-wireframe.sh          # assembles build/wireframe/
python3 -m http.server -d build/wireframe 8000
```

Then open <http://localhost:8000>. Opening `wireframe/index.html` straight
from disk works too, but without `requirements.js` the panel shows bare
identifiers instead of their titles and statuses.

## Using it

The television is laid out at 1920×1080, as tvOS is, and scaled to fit. Sizes
follow Apple's
[Human Interface Guidelines for tvOS layout](https://developer.apple.com/design/human-interface-guidelines/layout#tvOS):
content inside the 60 pt top and bottom and 80 pt side safe area, and tiles on
the five-column grid (320 pt wide, 40 pt apart), the same five-across layout
the tvOS home screen uses. Rows sit about 180 pt apart, artwork to artwork,
well above the HIG's 100 pt minimum, so two rows and the top of the third
show at once. Focusing a row that is partly off screen scrolls the page until
the whole row, captions included, sits inside the bottom safe area; going
back to the first row returns to the top.

| Input | Does |
| --- | --- |
| Arrow keys, or the remote's clickpad | Move focus |
| <kbd>Enter</kbd> / OK | Select; **hold** for the context menu |
| <kbd>Esc</kbd> / Menu | One level back |
| <kbd>Space</kbd> / play-pause | Play or pause in the player |
| Mouse | Click selects; right-click or long-press opens the context menu |
| Typing on the search screen | Goes straight into the field |

The panel beside the television lists the requirements behind whatever has
focus, and holds the scenarios the app has to cope with: approving sign-in on
a phone (with and without NPO Plus), an expired code, no network, a slow
backend, playback that fails, skipping to the credits, triggering "Kijk je
nog?", and moving the clock on a day to watch finished items leave recently
watched after seven days. State is kept in the browser's local storage;
*Restore the example data* and *Start empty* reset it.

The catalogue in `data.js` is invented. It includes an expired series, film
and episode, so the unavailable states can be seen. In normal mode the example
has nine pinned series, eleven recently watched items and seven saved for
later, more than the five a row shows, so every row scrolls sideways as it
will on a television. Only series are pinned (FR-HOME-03); films and
standalone episodes go on watch later.

## What the wireframe decides that the requirements do not

These are placeholders chosen to make the sketch work. Each is open until a
requirement settles it; if one is right, the requirement should say so.

- **Labels.** *Kindermodus* and *Gewone modus* for the modes; *Vastgezet*,
  *Recent bekeken* and *Later kijken* for the rows (only the last is named in
  FR-LATER, as a working label).
- **Where the controls sit.** Search, the mode switch and settings share a bar
  above the rows; initial focus is the first pinned tile, one press below
  search (FR-HOME-01, FR-SEARCH-01, FR-MODE-02).
- **The context menu** on a long press of OK is the "discoverable" route for
  unpin, remove and save on a tile (NFR-A11Y-01); the detail page is the
  second route.
- **Kids mode's identity**: a rounded typeface, rounder tiles and buttons, a
  stitched frame around the screen and a *Kindermodus* badge on every screen
  (FR-MODE-03, NFR-A11Y-04). Tiles keep the same size as in normal mode, so
  both modes show three rows.
- **Timings**: the still-watching grace period is 30 seconds (FR-PLAY-08 says
  "a defined grace period"); the next-episode overlay in normal mode shows for
  8 seconds (FR-PLAY-05, "long enough to be used").
- **Setting choices**: kids pause 0/5/10/15/30 s; kids still-watching
  30 min–2 h; normal still-watching 1–4 h (FR-SET-02 asks for "a small set of
  sensible choices").
- **Recent searches** are capped at ten terms (FR-SEARCH-04 asks for "a fixed
  number").
- **Settings in two columns**: playback timings on the left, account and
  local data on the right, so the page fits without scrolling. The account
  group says the television is signed in with NPO Plus, which the app knows
  from the subscription check (FR-AUTH-08); no requirement asks for that line.
- **A fully watched series** has no play button on its detail page; the page
  says so and offers the episode list. No requirement says what the primary
  action is in that case.

## Files

| File | Holds |
| --- | --- |
| `index.html` | The page: television, remote and panel |
| `style.css` | Both worlds: the themed page and the fixed tvOS canvas |
| `data.js` | The invented catalogue |
| `app.js` | State, screens, focus navigation and the scenarios |
| `requirements.js` | Generated by `scripts/build-wireframe.sh`; not committed |
