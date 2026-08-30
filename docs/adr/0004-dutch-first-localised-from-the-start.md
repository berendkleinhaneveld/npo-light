# 0004. Dutch first, localised from the start

- **Status:** Accepted
- **Date:** 2026-08-30
- **Deciders:** @berendkleinhaneveld

## Context

NPO light shows Dutch public broadcasting to a Dutch family, so the interface
is Dutch. That much was never in question; what was open
([Q-05](../requirements/open-questions.md)) is whether the app should be
*written* as a Dutch app or as a translatable one that happens to ship Dutch.

The project is built in the open, so other people may want it in another
language. Localisation is also the kind of change that is disproportionately
expensive to retrofit: every view, every alert, every accessibility label,
every assembled sentence and every hand-built duration has to be found and
rewritten, and the tests that assert on Dutch text have to be rewritten with
them. Doing it from the first view costs a String Catalog and a habit.

tvOS and SwiftUI make the cheap path the correct one: a `String` literal passed
to `Text` is a `LocalizedStringKey` and is looked up automatically, so a view
written the natural way is already localised. The traps are elsewhere — text
built in model code, sentences glued from fragments, and durations formatted by
hand, all of which this app needs for countdowns, episode counts and remaining
times.

## Decision

Dutch is the base localisation, and the app is internationalised from the first
view. All user-facing text lives in a String Catalog (`.xcstrings`); views rely
on SwiftUI's automatic lookup and everything else uses `String(localized:)`.
Varying text uses format arguments and the catalogue's plural variants rather
than concatenation, and dates, times, durations and numbers go through
locale-aware formatters.

Tests assert on catalogue keys or looked-up values, never on Dutch literals, so
that adding a language cannot turn the suite red.

The requirements are `NFR-I18N-01` to `NFR-I18N-03` in
[`docs/requirements/nfr-localisation.md`](../requirements/nfr-localisation.md).
`NFR-A11Y-05`, written before the question was answered, is superseded by
`NFR-I18N-01`.

## Alternatives considered

- **Hard-code Dutch, localise later if anyone asks** — rejected. It is the
  cheapest thing to do today and the most expensive to undo, and "later"
  arrives after every view has been written.
- **English base with a Dutch translation** — rejected. The audience is Dutch
  and the content is Dutch; an English base would mean the family sees a
  translation of the developer's language, and every string would be written
  twice from day one.
- **Dutch literals in views, catalogue only for the rest** — rejected. It is
  the same trap in a smaller box: the split has to be maintained by hand, and
  it puts exactly the strings a translator needs out of reach.

## Consequences

- Every user-facing string needs a catalogue entry, including throwaway ones
  during development. This is friction, and it is the point.
- Tests cannot assert on the text a user reads without going through the
  catalogue, which makes them slightly more indirect and considerably more
  durable.
- Layouts must tolerate longer translations, which on tvOS overlaps with
  tolerating larger accessibility text sizes (`NFR-A11Y-03`) — one concern to
  design for, not two.
- Adding a language later requires no code change, so a contributor can offer
  one without touching the app.
- Reversing this would mean inlining the catalogue back into the views; nothing
  else depends on it.
