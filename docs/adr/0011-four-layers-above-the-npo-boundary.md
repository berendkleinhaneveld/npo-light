# 0011. Four layers above the NPO boundary

- **Status:** Accepted
- **Accepted:** 2026-09-20
- **Date:** 2026-09-03
- **Deciders:** @berendkleinhaneveld

## Context

[ADR 0008](0008-one-boundary-around-the-npo-backend.md) and
[ADR 0009](0009-test-doubles-at-two-seams.md) describe the bottom edge of the
app. Nothing describes what stands on it, and what stands on it today is Xcode's
template: a `NavigationSplitView` (an iPad shape), an `@Model` called `Item`
(colliding with the word the requirements reserve for a series, a film or a
standalone episode), and a `fatalError` on a failed `ModelContainer` (the crash
loop NFR-REL-05 forbids).

Of ninety-four requirements, ninety-two are `Accepted`, one is `Implemented`
and one is `Superseded`. They say what
the app does, not what a view may know or where a decision lives — and that
cannot be read off them: NFR-MAINT-03 wants decisions testable without a view,
NFR-PERF-05 wants persistence off the main actor, and FR-MODE-02 and FR-AUTH-03
make mode and session two scopes that change under any screen.

One person would settle this implicitly. Agents taking one requirement cluster
each will not: every change is locally reasonable and the shapes do not agree.

## Decision

Four layers, composed in `NPOLightApp` and reached by injection. No singletons,
no `.shared`, no global mutable state.

**Stores** — one per local concern: pins, recently watched, progress, watch
later, search history. Actors with their own `ModelContext`, so persistence is
off the main actor (NFR-PERF-05), and the only types that know the schema exists
([ADR 0012](0012-what-the-local-store-holds.md)). They return value types, never
a `@Model` instance, which is not `Sendable`.

**Every store method takes the mode as an argument**, and no store reads an
ambient one. FR-MODE-05 breaks silently — a child's viewing on the adult home
page is not a crash — so the scope belongs in the signature, where a reviewer and
a test can both see it.

**Coordinators** — where a rule spans stores. One to begin with: ADR 0006's
finish fans out three ways (FR-HOME-04, FR-LATER-07, FR-HOME-07), so a
`PlaybackCoordinator` owns the threshold (FR-PLAY-04), interval persistence
(FR-PLAY-03), autoplay (FR-PLAY-05 to FR-PLAY-07) and still-watching
(FR-PLAY-08).

**Screen models** — one `@MainActor @Observable` per screen, holding what it
renders and its navigation path, exposing intents as methods. Session and mode
belong to no screen: one `AppModel` holds both (FR-AUTH-01, FR-MODE-01), and
`RootView` switches on the session.

**Views** — given a screen model. **No `@Query`, no
`@Environment(\.modelContext)`.** One `NavigationStack` rooted at home over a
value-typed `Destination`; the player is presented over it rather than pushed,
since FR-PLAY-05 continues into the next episode within one playback session.

## Alternatives considered

- **`@Query` and `@Environment(\.modelContext)` in views** — the template's
  shape, and what AGENTS.md prescribed before this decision. Rejected: persistence on the main
  actor (NFR-PERF-05), decisions in an untestable place (NFR-MAINT-03), and it
  does not reach — FR-HOME-04 resolves a pinned series to its next unwatched
  episode through the *backend*, and FR-HOME-06 filters on a computed threshold
  under a cap.
- **One app-wide store object** — rejected: the file every parallel agent edits
  at once, with nothing smaller than the whole app to test.
- **A view model per view, including tiles** — rejected as ceremony; the unit is
  the screen.
- **An architecture package (TCA or similar)** — rejected: a dependency needing
  its own ADR, buying least in an app whose state is two scopes and five lists.

## Consequences

- **AGENTS.md's SwiftData guidance now follows this decision**: stores own the
  contexts and views receive screen models. The architecture and the instructions
  agents read first must stay in agreement.
- **FR-HOME-10 becomes explicit work.** No `@Query` means no automatic change
  tracking: a screen model re-reads when it becomes active and when a coordinator
  says something changed. That is the price of this decision, paid in the home
  page's pull request.
- Stores returning value types means a mapping layer between `@Model` and structs
  — dull code that keeps `Sendable` honest without the escape hatches AGENTS.md
  forbids.
- Cheap to reverse now, expensive once the home page exists.
