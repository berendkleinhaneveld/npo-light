# Search

Search is the app's way of finding anything that is not already on the home
page, and it has to stay fast under the thumb. Prefix `FR-SEARCH`.

## FR-SEARCH-01 — Search is one action from home

- **Status:** Accepted

The search page is reachable from the home page in a single remote action, in
both modes.

**Acceptance criteria**

- Home offers search without opening a menu first.
- Opening search puts focus on the text field, ready to type.
- Leaving search returns to home with the previous focus restored.

## FR-SEARCH-02 — Results appear as you type

- **Status:** Implemented

Results update while the user types; there is no separate "search" button to
press.

**Acceptance criteria**

- Typing more characters narrows the results without further action.
- Deleting characters widens them again.
- Results show enough to recognise an item: artwork, title, and whether it is a
  series or something that plays (FR-CONTENT-01).

## FR-SEARCH-03 — Typing is never blocked

- **Status:** Implemented

Characters appear on screen as fast as the user presses them, no matter what
the network is doing. No fetching, decoding or persisting happens on the main
actor.

**Rationale.** This is the single most annoying flaw in the official app, and
the reason this one exists. It is stated as a functional requirement because
the user experiences it as behaviour, and measured by NFR-PERF-01.

**Acceptance criteria**

- With a backend that never responds, every keystroke is still rendered and the
  field keeps accepting input.
- With a backend that takes seconds per request, the text field never lags a
  keystroke behind.
- Requests are debounced, and a superseded request is cancelled.
- Late results from a superseded request are discarded, never rendered: the
  results on screen always belong to the text in the field.

## FR-SEARCH-04 — An empty field shows recent searches

- **Status:** Accepted

With no text in the field, the search page shows recent search terms, most
recent first.

**Acceptance criteria**

- Opening search with no text shows recent terms rather than an empty page.
- Clearing the field returns to the recent terms.
- With no history at all, the page says so instead of showing an empty band.
- The list is capped at a fixed number of terms; the oldest is dropped.

## FR-SEARCH-05 — A recent search remembers what was picked

- **Status:** Accepted

When the user opens or plays an item from a set of results, that item is
recorded against the search term. The recent-search tile then shows the term
together with the item or items picked for it.

**Example.** Typing `Fr` returns *Freeks Wilde Wereld* and *Freek in het wild*.
Picking *Freeks Wilde Wereld* means the next visit to search shows a `Fr` tile
carrying *Freeks Wilde Wereld*.

**Acceptance criteria**

- Picking an item stores it against the exact term that was in the field.
- Searching the same term again and picking another item adds that item to the
  same term, without duplicating the term.
- Picking the same item twice does not duplicate it; it moves to the front.
- A term with no pick is still remembered, as a term on its own.

## FR-SEARCH-06 — A recent search is two shortcuts

- **Status:** Accepted

From a recent-search tile the user can either re-run the whole search or go
straight to a previously picked item.

**Acceptance criteria**

- Selecting the term puts it in the field and runs the full search again.
- Selecting a picked item on the tile opens that item directly, without
  searching.
- Both routes are reachable with the remote (NFR-A11Y-01).

## FR-SEARCH-07 — Delete a recent search

- **Status:** Accepted

The user can delete a recent search term, and can clear the whole history.

**Acceptance criteria**

- Deleting a term removes it and the items picked for it, immediately and
  permanently.
- Deleting a term does not unpin anything and does not touch recently watched.
- Clearing all history asks for confirmation first.
- Clearing history in one mode leaves the other mode's history alone
  (FR-MODE-05).

## FR-SEARCH-08 — Kids mode searches the youth catalogue

- **Status:** Accepted

In kids mode, search returns only youth-catalogue items (FR-MODE-04).

**Acceptance criteria**

- A term that matches adult content in normal mode returns none of it in kids
  mode.
- The restriction is applied to the request, not by filtering a full result set
  after the fact, where the backend allows it.

## FR-SEARCH-09 — No results is a state, not a blank page

- **Status:** Implemented

A search that matches nothing says so.

**Acceptance criteria**

- An empty result set shows a message naming the term that was searched.
- A search that fails because of the network shows a retry, distinct from "no
  results" (NFR-REL-02).
- Neither state hides the text field or loses what was typed.

## FR-SEARCH-10 — Results are grouped by kind

- **Status:** Implemented

Search results are shown in up to three rows, in this order: series, single
programmes, episodes. A row with nothing in it is not shown.

**Rationale.** NPO answers a search with series in one list and everything
playable in another, where a film sits among the episodes. A search for a
film's name is answered with every episode of every series that shares a word
with it, and the film at the end: searching for "substance" gave eight episodes
of a series and then the film. What stands alone is what was most likely
looked for, so it comes before the episodes.

**Acceptance criteria**

- A programme that belongs to no series (FR-CONTENT-01) is in the row of single
  programmes and not among the episodes.
- The row is headed *Films en losse programma's*: the app knows that a
  programme stands alone, not whether it is a film.
- A programme NPO does not mark either way is shown among the episodes, which
  is what nearly all programmes are.
- Within a row the order is NPO's.
