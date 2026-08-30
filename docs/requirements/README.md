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
| [home.md](home.md) | `FR-HOME` | The home page: pinned and recently watched |
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

## Identifiers

`<PREFIX>-<AREA>-<NN>`, for example `FR-SEARCH-03` or `NFR-PERF-01`.

An identifier is permanent. When a requirement changes meaning, retire the old
one (status `Superseded`, with a pointer) and add a new number — never
renumber, and never recycle a number, because tests, commits and pull requests
refer to it.

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

1. Pick a requirement that is `Accepted`.
2. Write the failing test, naming the identifier.
3. Make it pass, keeping the build lint-clean and warning-free.
4. Flip the status to `Implemented` in the same pull request.

Changing *what* the app should do means changing a file here first. A pull
request that adds behaviour nothing in this directory asks for is a pull
request that needs a requirement, or needs to be smaller.
