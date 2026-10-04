# 0017. Load artwork at the size it is shown, off the main actor

- **Status:** Proposed
- **Date:** 2026-10-04
- **Deciders:** @berendkleinhaneveld

## Context

Every image came through SwiftUI's `AsyncImage`, given the address exactly as
NPO lists it. Moving along the search keyboard stuttered whenever a set of
results arrived — the one thing FR-SEARCH-03 exists to prevent.

Three facts, measured against `assets-start.npo.nl` on 2026-10-04:

- The address NPO lists is the **original**: 3024 × 1701 pixels and about
  430 KB for a tile drawn 320 points wide. Decoded, that is 20 MB per tile.
- `AsyncImage` decodes when the image is first drawn, **on the main thread**,
  and keeps nothing: a tile that leaves the screen and comes back — every
  keystroke replaces the results — fetches and decodes again.
- The host scales, but only for the sizes it knows. `?dimensions=375x375`,
  `600x600` and `1200x1200` answer with an image fitted inside that square
  (600 × 337, 37 KB); any other value, `640x360` included, is ignored and
  answered with the original. NPO's own site asks for exactly these three.
  Responses carry `cache-control: max-age=31536000`.

NFR-PERF-05 asks for image decoding off the main actor and NFR-PERF-04 for an
artwork cache with a documented ceiling. Neither can be had from `AsyncImage`.

## Decision

We load images ourselves, through an injected `ArtworkProviding`.

- **Asked for at a size.** `ArtworkSize` is an enumeration of what the host
  will make — `tile` (600) and `large` (1200) — and puts `dimensions` on the
  address. A view names the size, never a number of pixels. One more, `full`,
  is for the image across a series' page: the host makes nothing between 1200
  and the original, so it asks for the original and decodes it no wider than
  1920 pixels — 8 MB in memory, for the one image a page has.
- **Decoded where it is fetched.** `ArtworkLoader` is `@concurrent`: it
  fetches, and decodes with ImageIO to pixels no larger than the size asked
  for, before anything reaches the main actor. That also holds when the host
  ignores the size and sends the original.
- **Kept in memory under a ceiling.** Decoded images are kept up to 64 MB,
  counted in bytes of pixels, least recently used out first. What is in memory
  is read without waiting, so a tile that comes back draws in its first frame.
- **Kept on disk by the system.** The images have a `URLSession` of their own
  with a `URLCache` of 128 MB on disk — in `Caches`, which tvOS may empty
  ([ADR 0015](0015-local-data-in-two-places.md)), and nothing is lost when it
  does.
- **Reached through the environment.** `NPOLightApp` sets
  `EnvironmentValues.artwork` once. The default is `NoArtwork`, which leaves
  every placeholder in place: what a preview gets, and the app as a test
  launches it.

The images do not go through `LoggingTransport`: with `NPO_LIGHT_HTTP_LOG=full`
it would write every image to a file. A failed image is still logged, by the
loader, with the host and the error and not the path (NFR-DIAG-01).

## Alternatives considered

- **Keep `AsyncImage`, and only add `dimensions` to the address** — the
  smallest change, and it removes most of the cost. Rejected: decoding stays
  on the main thread, nothing is kept in memory, and an address the host does
  not scale is back to 20 MB without anyone noticing.
- **An image library (Nuke, Kingfisher)** — does all of this and more.
  Rejected: the app has no dependencies, and what is needed here is two
  hundred lines.
- **Pass the loader through every screen model**, as the catalogue is —
  what [ADR 0011](0011-four-layers-above-the-npo-boundary.md) does for
  everything else. Rejected for this one: an image is drawn by a tile five
  views down from any screen, and has no decision in it for a screen model to
  own. The environment is still injection from the composition root, not a
  shared instance.
- **`NSCache`** — evicts on its own schedule and cannot say what it holds, so
  the ceiling NFR-PERF-04 asks for could not be asserted.

## Consequences

- A view that shows an image uses `ArtworkView` and says which size. A new
  size on screen means checking that the host makes it before adding a case.
- A fetch is not called off when its tile goes away. The images are small, and
  the next thing typed tends to want them; the cost is a few requests that
  finish for nothing.
- Tiles are 640 pixels wide on a 4K television and get 600. That is the
  nearest size the host has; the next is twice the bytes.
- The memory ceiling is a guess for a device with 3–4 GB, to be revisited when
  the home page shows several rows at once.
- If NPO moves its images or stops scaling, the loader still scales them down
  itself — slower to fetch, but not back on the main thread.
