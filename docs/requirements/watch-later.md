# Watch later

A list of single things the family means to watch once: this film, that one
documentary episode. Prefix `FR-LATER`.

Watch later is not pinning. A **pin** says "we follow this series, keep giving
us the next episode" (FR-HOME-03); a **saved** item says "this one thing, and
then it is done". The two lists are independent: an episode of a pinned series
can also be saved, and unpinning the series does not empty the list. Why the
two lists are kept apart is
[ADR 0005](../adr/0005-watch-later-is-a-separate-episode-level-list.md).

The row and its action are called *Later kijken* in the working copy of these
requirements; the wording that ships is a String Catalog entry (NFR-I18N-01),
not something these requirements fix.

## FR-LATER-01 — Watch later is its own list

- **Status:** Accepted

The app keeps a watch later list per mode, separate from pinned items
(FR-HOME-02) and from recently watched (FR-HOME-12). Saving, unsaving and
playing a saved item never change what is pinned.

**Acceptance criteria**

- Saving an item does not pin it, and pinning an item does not save it.
- Unpinning a series leaves any saved episode of that series on the list.
- Erasing the list leaves pins, playback positions and history untouched
  (FR-SET-05).
- The list survives relaunch.

## FR-LATER-02 — Only films and single episodes can be saved

- **Status:** Accepted

What can be saved is one playable thing: a **film**, a **standalone episode**,
or **one episode of a series**. A series itself cannot be saved — a series is
something you follow, so it is pinned instead (FR-HOME-03).

**Rationale.** The inverse of pinning. Pinning is series-level and cannot hold
a single episode; watch later is episode-level and cannot hold a series.
Between them every "we want to watch that" has exactly one home.

**Acceptance criteria**

- An episode of a series can be saved on its own, without the series being
  pinned or saved.
- A film and a standalone episode save as themselves.
- The save action is absent — not merely inert — on a series' own detail page,
  which offers the pin action instead.
- Saving an item that is already saved does not create a second entry; the
  action reads as already-saved and offers removal (FR-LATER-09).
- Two episodes of the same series are two separate entries, each shown as its
  own tile.

## FR-LATER-03 — Saving is offered wherever an item is

- **Status:** Accepted

An item can be saved from every place the app already shows it, without
navigating somewhere else first.

**Acceptance criteria**

- From an item's detail page, alongside the play and pin actions
  (FR-CONTENT-03).
- From a series' episode list, per episode, without opening that episode's
  detail page.
- From a search result, without opening its detail page (FR-SEARCH-02).
- From a recently watched tile, so something already started can be moved onto
  the deliberate list (FR-HOME-12).
- In every one of those places the action toggles: it saves an unsaved item and
  removes a saved one, and its label says which it will do.
- The action is reachable from the remote without a hidden gesture being the
  only route (NFR-A11Y-01).

## FR-LATER-04 — Most recently saved first

- **Status:** Accepted

The list is ordered by when each item was saved, most recent first — the same
convention as the pinned row (FR-HOME-02).

**Acceptance criteria**

- Saving an item puts it at the front of the row.
- Re-saving an item that was removed moves it to the front; it does not return
  to its old place.
- The order survives relaunch.

## FR-LATER-05 — A third home row, below recently watched

- **Status:** Accepted

Watch later is the third row of the home page, below recently watched
(FR-HOME-11). When the list is empty the row is not shown at all.

**Rationale.** Continue-watching is what the family reaches for most, so it
keeps its place near the top. A household that never saves anything sees the
two rows it saw before, not an empty band explaining a feature it does not use
— which is why this row is the one exception to FR-HOME-09.

**Acceptance criteria**

- The row order on home is pinned, recently watched, watch later.
- With an empty list the row and its heading are absent, and focus behaves as
  if the page had two rows.
- Saving the first item makes the row appear without a manual refresh
  (FR-HOME-10); removing the last item makes it disappear the same way, and
  focus moves somewhere usable rather than being lost.
- Each tile identifies what will play: the film's title, or the episode's title
  with the series it belongs to.

## FR-LATER-06 — The list is not capped

- **Status:** Accepted

Watch later holds as many items as the family saves. Nothing is dropped to make
room.

**Rationale.** Recently watched is a by-product of watching and can be trimmed
silently (FR-HOME-12); this list is a set of deliberate choices, and silently
discarding one loses something the user asked the app to remember. A row that
grows uncomfortably long is a sign to watch something, not a bug.

**Acceptance criteria**

- Saving items beyond any number the recently watched cap uses removes nothing.
- The row scrolls rather than truncating, and its performance does not degrade
  visibly as it grows (NFR-PERF-02).

## FR-LATER-07 — Finishing an item removes it

- **Status:** Accepted

When playback of a saved item passes the completion threshold (FR-PLAY-04), it
leaves the watch later list. The list empties itself as the family works
through it.

**Acceptance criteria**

- Finishing a saved film or episode removes it from the list, whether it was
  played from the watch later row or from anywhere else in the app.
- Removal is immediate on return from playback (FR-HOME-10) and survives
  relaunch.
- It leaves the watch later list at once, while the recently watched row keeps
  it for seven days as a finished tile (FR-HOME-13) — the two lists answer
  different questions, and only this one is a queue.
- What was watched stays marked watched, so next-episode logic is unaffected.
- Finishing a saved episode of a series does not save the next episode; a
  saved episode is one thing, not a subscription.
- The item can be saved again afterwards, and then sits at the front of the row
  (FR-LATER-04).

## FR-LATER-08 — A started item stays until it is finished

- **Status:** Accepted

Playing part of a saved item does not remove it. It remains on the list, with
its progress, until it passes the completion threshold or is removed by hand.

**Acceptance criteria**

- After stopping halfway, the item is in both the recently watched row and the
  watch later row, and both tiles show the same progress (FR-PLAY-03).
- Playing it again from either row resumes at the stored position
  (FR-PLAY-02).
- Removing it from recently watched (FR-HOME-08) leaves it on the watch later
  list — but, since that discards the stored position, its tile then shows no
  progress.

## FR-LATER-09 — Remove by hand

- **Status:** Accepted

A saved item can be taken off the list without watching it, from the watch
later row itself and from its detail page.

**Acceptance criteria**

- Removing from the row takes the tile away immediately, without leaving the
  home page, and it does not come back on relaunch.
- Removing does not discard the item's playback position and does not touch
  recently watched or pins.
- Removing the last item hides the row (FR-LATER-05).

## FR-LATER-10 — Each mode has its own watch later list

- **Status:** Accepted

Watch later is stored per mode, like pins, history and search history
(FR-MODE-05). What a child saves is not on the adult home page, and the other
way round.

**Acceptance criteria**

- Saving an item in one mode does not add it to the other mode's list.
- The same episode may be saved in one mode and not in the other; the toggle in
  FR-LATER-03 reflects the current mode only.
- Only items from the youth catalogue can be saved in kids mode, since only
  those are shown there (FR-MODE-04).
- Erasing one mode's data empties that mode's list only (FR-SET-05).

## FR-LATER-11 — A saved item that disappears

- **Status:** Accepted

Rights expire, and a saved item may be gone by the time the family gets to it.
That must not break the home page (FR-CONTENT-05).

**Acceptance criteria**

- A saved item that can no longer be fetched keeps its tile, shown as
  unavailable with its cached title, and can still be removed.
- Selecting it explains that it is no longer available instead of failing to
  play.
- An unavailable item is not removed from the list on the app's own initiative;
  the user decides.

## FR-LATER-12 — Playing from the row

- **Status:** Accepted

A tile in the watch later row plays that exact item.

**Acceptance criteria**

- The tile plays the saved film or episode itself, never the next episode of
  its series and never the series' detail page.
- Playback resumes at the stored position when there is one (FR-PLAY-02).
- Starting playback moves the item to the front of recently watched
  (FR-HOME-12) while leaving it on the watch later list (FR-LATER-08).
- Autoplay of the following episode behaves exactly as it does elsewhere
  (FR-PLAY-05); what autoplay then plays is not itself saved.
