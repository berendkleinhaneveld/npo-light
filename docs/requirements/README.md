# Requirements

This directory is the specification of **NPO light**: a simplified tvOS app for
NPO Start / NPO Plus, built for family use. Every requirement has a stable
identifier so that a test can name the behaviour it proves.

One file per area. Functional requirements describe *what the app does*;
non-functional requirements describe *how well it has to do it*.

## Index

| File | Prefix | Area |
| --- | --- | --- |
| [content.md](content.md) | `FR-CONTENT` | Items, series, episodes and the catalogue behind them |
| [account.md](account.md) | `FR-AUTH` | NPO Plus sign-in and session handling |
| [modes.md](modes.md) | `FR-MODE` | Normal mode and kids mode |
| [home.md](home.md) | `FR-HOME` | The home page: pinned, recently watched and the rows' behaviour |
| [watch-later.md](watch-later.md) | `FR-LATER` | Single films and episodes saved to watch once |
| [search.md](search.md) | `FR-SEARCH` | Search and search history |
| [playback.md](playback.md) | `FR-PLAY` | Playing, resuming, autoplay and still-watching |
| [settings.md](settings.md) | `FR-SET` | Configuration and local data management |
| [nfr-performance.md](nfr-performance.md) | `NFR-PERF` | Responsiveness, above all while typing |
| [nfr-reliability.md](nfr-reliability.md) | `NFR-REL` | Network failures, caching, data durability |
| [nfr-privacy.md](nfr-privacy.md) | `NFR-PRIV` | Local-only data, credential handling |
| [nfr-accessibility.md](nfr-accessibility.md) | `NFR-A11Y` | Remote navigation and VoiceOver |
| [nfr-localisation.md](nfr-localisation.md) | `NFR-I18N` | Dutch first, translatable from the start |
| [nfr-maintainability.md](nfr-maintainability.md) | `NFR-MAINT` | How the code and its tests are kept honest |
| [out-of-scope.md](out-of-scope.md) | — | What this app deliberately does not do |
| [open-questions.md](open-questions.md) | `Q` | Unknowns that block a requirement until answered |

## Vocabulary

- **Item** — anything the user can pin, find or watch: a **series**, a **film**
  or a **standalone episode**. Where a rule holds for all three, it says
  "item".
- **Episode** — one playable instalment of a series.
- **Mode** — *normal mode* or *kids mode*. The app is always in exactly one.
- **Pinned** — an item the user deliberately put on the home page.
- **Recently watched** — items the user played, most recent first; the app's
  "continue watching" list.
- **Saved** — a film or a single episode put on the watch later list, to be
  watched once and then dropped from it (FR-LATER-01).

## Identifiers

`<PREFIX>-<AREA>-<NN>`, for example `FR-SEARCH-03` or `NFR-PERF-01`.

An identifier becomes permanent when something refers to it. Once a requirement
is `Implemented` — a test names it — a change of meaning retires the old number
(status `Superseded`, with a pointer) and adds a new one.

Until then it is a draft: rewrite it in place, keep its identifier, and let git
carry the history. A retired number is never reused.

## Status values

| Status | Meaning |
| --- | --- |
| `Proposed` | Written down, not yet agreed — usually waiting on an open question. |
| `Accepted` | Agreed and ready to be built. No implementation yet. |
| `Implemented` | Code exists **and** at least one test references the identifier. |
| `Deferred` | Agreed in principle, deliberately not in the current scope. |
| `Superseded` | Replaced; the entry says by which identifier. |

## Linking tests to requirements

A test names the requirement it proves in its display name:

```swift
@Test("FR-SEARCH-03: typing is not blocked by a slow backend")
func typingStaysResponsive() async throws {
    // ...
}
```

For a test that covers more than one requirement, list them all
(`@Test("FR-HOME-04, FR-PLAY-02: ...")`). Where a display name would be
awkward — a UI test helper, an extension — a `// Requirement: FR-HOME-04`
comment counts too.

`./scripts/requirements-coverage.sh` reads this directory and the two test
targets and reports the mapping. It fails when:

- a test references an identifier that does not exist here (a typo, or a
  requirement that was renumbered);
- a requirement marked `Implemented` has no test referencing it;
- an identifier is defined twice, or a requirement has no `Status`.

It runs in CI. A requirement that is `Accepted` but untested is not an error —
that is simply work that has not been done yet.

## The development loop

The app is written by coding agents under the repository owner's supervision,
test-first:

1. Pick the smallest coherent piece of work — usually one `Accepted`
   requirement, sometimes a handful that share a screen or a data model.
2. Write the failing tests, each naming the identifier it proves.
3. Make them pass, keeping the build lint-clean and warning-free.
4. Flip the status of every requirement the change implements, in the same
   pull request, and name them in its description.

**How many at once?** As many as one reviewable change honestly covers, and no
more. Some requirements only make sense together: `FR-SEARCH-04` to
`FR-SEARCH-07` are one search-history store seen from four angles, and building
them separately means writing that store four times. Others are cross-cutting
and are never a change of their own: the accessibility and localisation
requirements are conditions every screen has to meet, so tests name them again
and again, and they reach `Implemented` only once they hold everywhere they
apply.

What matters is not the count. It is that every requirement a change implements
is named, and that nothing is implemented that no requirement asks for.

Changing *what* the app should do means changing a file here first. A pull
request that adds behaviour nothing in this directory asks for is a pull
request that needs a requirement, or needs to be smaller.
