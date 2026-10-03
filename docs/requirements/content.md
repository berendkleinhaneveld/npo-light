# Items and catalogue

What the app can show and play, and where that information comes from.
Prefix `FR-CONTENT`.

## FR-CONTENT-01 — Three kinds of item

- **Status:** Accepted

The app models exactly three kinds of item: a **series** (an ordered collection
of episodes), a **film**, and a **standalone episode** that belongs to no
series. Every item has a stable identifier, a title, a description and artwork.

**Acceptance criteria**

- An item's identifier is stable across launches and app updates, and is what
  pins, watch history and search history store.
- A film and a standalone episode are directly playable; a series is not — one
  of its episodes is.
- Artwork may be missing; the app renders a placeholder rather than an empty
  tile.

## FR-CONTENT-02 — A series exposes its episodes in order

- **Status:** Accepted

A series exposes its seasons and, within a season, its episodes in broadcast
order, so that "the next episode" is well defined.

**Acceptance criteria**

- Given an episode of a series, the app can determine the following episode, or
  determine that there is none.
- The last episode of a season is followed by the first episode of the next
  season, if one exists.
- An episode that is in the catalogue but not playable (expired rights) is
  skipped when looking for the next episode, and is shown as unavailable in an
  episode list.

## FR-CONTENT-03 — Item detail page

- **Status:** Accepted

Selecting an item anywhere in the app opens its detail page: title,
description, artwork and a play or resume action. A series adds a pin or unpin
action and its episode list with watched state per episode, browsed a season at
a time (FR-CONTENT-07) with a preview of each episode (FR-CONTENT-08); a film or
a standalone episode adds a save action instead (FR-HOME-03, FR-LATER-03).

**Acceptance criteria**

- The primary action reads *Afspelen* for an unwatched item and *Verder kijken*
  for one with a stored position (FR-PLAY-02).
- For a series, the primary action plays the next unwatched episode
  (FR-HOME-04).
- On a series, the pin action reflects the current pinned state and toggles
  it (FR-HOME-03, FR-HOME-05).

## FR-CONTENT-04 — Catalogue data comes from NPO and is cached

- **Status:** Accepted

Item metadata is fetched from NPO's backend and cached locally, so that a
screen the user has seen before can be rendered again without a network round
trip.

**Acceptance criteria**

- A cached response is used to render immediately; a refresh happens in the
  background and updates the view when it differs.
- Cache entries carry a fetch timestamp and are refreshed when older than a
  defined maximum age.
- The cache is bounded: it does not grow without limit as the family browses.
- Nothing about *what* was cached leaves the device (NFR-PRIV-01).

## FR-CONTENT-05 — An item that disappears does not break the app

- **Status:** Accepted

Items are removed from NPO's catalogue when their rights expire. A pinned or
recently watched item that no longer exists must not break the home page.

**Acceptance criteria**

- A tile whose item can no longer be fetched is shown as unavailable, with the
  cached title, and can still be removed or unpinned.
- Selecting an unavailable item explains that it is no longer available instead
  of failing to play.
- Autoplay skips an unavailable next episode (FR-CONTENT-02).

## FR-CONTENT-06 — Availability decides what is playable

- **Status:** Accepted

Every item says for whom and until when it can be watched. The app reads that
and decides whether an item is playable *now, for this account*, before it asks
for a stream.

**Rationale.** NPO's backend refuses a stream the account is not entitled to,
but entitlement is visible in the catalogue data long before that. The app
backend states it per item directly, as an indication of what this account may
do with it; the website states it as a set of dated windows. Either way,
reading it turns a failed request into a screen that explains itself and keeps
the app from asking for streams it cannot have
([Q-02](open-questions.md#q-02--which-npo-endpoints-back-search-catalogue-and-streams)).

**Subscription is not what this decides.** Every signed-in account has NPO Plus
(FR-AUTH-08), so "playable by this account" is not a question about the
subscription. What is left is still real: an item can be outside its window
altogether, withdrawn, or geographically restricted, and a recent episode can
be free now and behind Plus later without either state making it unplayable
here.

**Acceptance criteria**

- An item the backend marks as not playable by this account is treated as
  unavailable (FR-CONTENT-05), and no stream is requested for it.
- An item playable only with NPO Plus is playable, since the signed-in account
  always has it (FR-AUTH-08); it is not gated, hidden or marked differently
  from a free one.
- The decision uses the current time each time it is made, not a value cached
  from when the item was fetched.
- A stream the backend nevertheless refuses is reported as a playback error
  (FR-PLAY-10), not as a crash or a blank screen.

## FR-CONTENT-07 — A series is browsed one season at a time

- **Status:** Accepted

A series' detail page shows the episodes of one season at a time, with a season
picker above them that lists every season. Moving through the picker changes
the season shown.

**Rationale.** Some series run for decades: one programme on NPO has 27
seasons. One list of every episode makes the season you want hundreds of
presses away, and a page of every season's heading is not much better. A
picker makes any season a few presses away and keeps the list short enough to
read.

**Acceptance criteria**

- The page opens on the season that holds the episode the primary action would
  play (FR-HOME-04); for a fully watched series, on the first season.
- The picker shows one entry per season, in broadcast order, and the season
  being shown is distinguishable without colour (NFR-A11Y-04).
- Moving focus along the picker shows that season's episodes without a further
  press, and coming back up from the episode list lands on the season being
  shown, not on the first one (NFR-A11Y-01).
- With 27 seasons, every season is reachable from the picker without scrolling
  through another season's episodes.
- A series with a single season shows no picker.
- An unavailable episode keeps its place in its season's list (FR-CONTENT-02).

## FR-CONTENT-08 — An episode can be judged before it is played

- **Status:** Accepted

A series' detail page shows the series' header image, and the episode that has
focus in the list is previewed beside it with its own image and description.
The list itself stays compact — one line per episode — so a season can be
scanned at a glance.

**Rationale.** For a series that tells one story, the next episode is all that
matters and the list is a progress bar. For a series that is a collection —
episodes about one subject each, watched in any order — the title alone is
often not enough to choose by. NPO supplies an image and a description for
every episode; showing them for the focused episode helps choose without
turning the list into a wall of thumbnails.

**Acceptance criteria**

- The top of a series' page shows the series' header image; a film's or a
  standalone episode's page shows its own.
- Focusing an episode in the list shows its image, title, duration, watched
  state and description beside the list, without a press and without leaving
  the list.
- Each episode takes one line in the list: its title, NPO's own caption for it
  — which carries the episode number and the duration, such as `Afl. 1 • 10m` —
  and its watched state (NFR-A11Y-04). The caption is shown as NPO gives it; the
  app does not take a number out of it, and takes the order from the list.
- A missing image is drawn as a placeholder (FR-CONTENT-01), and a missing
  description leaves no empty box.
- The preview is announced with the focused episode, so VoiceOver reads the
  description too (NFR-A11Y-02).
