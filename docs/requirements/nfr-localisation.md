# Localisation

Prefix `NFR-I18N`. Dutch is what the family sees; internationalisation is how
the code is written, from the first view onwards.

## NFR-I18N-01 — Dutch is the base language, and every string is localised

- **Status:** Accepted

The interface is Dutch. It is Dutch *by translation*, not by hard-coding: the
project has a Dutch base localisation and a String Catalog, and every
user-facing string resolves through it.

**Rationale.** Retrofitting localisation means a sweep of every view, every
alert and every accessibility label — the kind of change that is never worth
doing later. Doing it from the first view costs almost nothing.

**Acceptance criteria**

- The project has a String Catalog (`.xcstrings`) with Dutch as its base
  localisation, and it is the only place user-facing text lives.
- Text in views goes through SwiftUI's automatic `LocalizedStringKey` lookup;
  text produced outside a view goes through `String(localized:)`. A user-facing
  `String` literal that reaches the screen by any other route is a defect.
- Accessibility labels and hints are localised too (NFR-A11Y-02).
- Adding a language means adding entries to the catalogue — no code change, no
  new view, no branch on locale.

## NFR-I18N-02 — Sentences are formatted, not assembled

- **Status:** Accepted

Text that varies — a countdown, an episode number, a remaining time — is built
with format arguments and plural variants, never by gluing fragments together.

**Rationale.** `"Nog " + count + " afleveringen"` cannot be translated into a
language that orders or inflects differently, and it gets the Dutch singular
wrong on its own.

**Acceptance criteria**

- No user-facing sentence is produced by concatenating or interpolating a
  translated fragment into another translated fragment.
- Quantities use the catalogue's plural variants, so one episode and five
  episodes both read correctly.
- Dates, times, durations and numbers are produced by locale-aware formatters,
  never hand-built from components.
- A duration renders correctly for a value of zero, and for one longer than an
  hour.

## NFR-I18N-03 — Translations cannot break the app

- **Status:** Accepted

Neither the tests nor the layouts depend on the interface being Dutch.

**Acceptance criteria**

- A test that asserts on user-facing text asserts on the catalogue key or the
  looked-up value, never on a Dutch literal typed into the test — so adding a
  translation does not turn the suite red.
- Layouts survive strings roughly half again as long as the Dutch ones without
  truncating a label to meaninglessness or breaking a row (NFR-A11Y-03 covers
  the same thing for larger text sizes).
- A missing translation falls back to the base language rather than showing a
  raw key.
