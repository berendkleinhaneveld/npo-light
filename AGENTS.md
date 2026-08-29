# AGENTS.md

Guidance for coding agents (and humans) working in this repository. Read this
before changing anything. If a rule here conflicts with a habit from another
project, the rule here wins.

## The project

**NPO light** is a tvOS app built with SwiftUI and SwiftData.

| | |
| --- | --- |
| Xcode project | `NPO light.xcodeproj` (shared scheme: `NPO light`) |
| Platform | tvOS, deployment target 26.2 |
| Language | Swift 5 language mode |
| App target | `NPO light/` — module name `NPO_light` |
| Unit tests | `NPO lightTests/` — Swift Testing (`import Testing`, `@Test`) |
| UI tests | `NPO lightUITests/` — XCTest (`XCUIApplication`) |
| Decisions | `docs/adr/` |

The app and test targets use Xcode's synchronised file groups: a `.swift` file
placed in one of those directories is part of the target automatically, and
`project.pbxproj` does not need to be touched to add or rename a file.

## The three checks

Run all three before you push. CI runs exactly the same scripts, so a green run
locally means a green run on GitHub.

```sh
./scripts/lint.sh    # SwiftLint, strict; also blocks lint exceptions
./scripts/build.sh   # xcodebuild, warnings are errors
./scripts/test.sh    # unit + UI tests on a tvOS simulator
```

`build.sh` and `test.sh` need macOS with Xcode. `lint.sh` does not — see below.

### Linting on Linux

There is no excuse for pushing unlinted code from a Linux container. SwiftLint
publishes a statically linked Linux binary that needs no Swift toolchain:

```sh
./scripts/install-swiftlint-linux.sh   # installs into ~/.local/bin
./scripts/lint.sh                      # picks up swiftlint-static from PATH
```

It runs every rule except the few that need SourceKit
(`literal_expression_end_indentation`, `statement_position`,
`vertical_whitespace_closing_braces`, `vertical_whitespace_opening_braces`),
and it names each one it skips on stderr. So a clean local run is strong
evidence, not proof: CI on macOS is the authority.

Building and testing still need Xcode. When you cannot run them, say so
explicitly in your summary rather than implying the change compiles.

## Rule 1: no lint exceptions

SwiftLint runs with `--strict`, so **every violation, including one reported as
a warning, fails the build.**

Not allowed, in code or in configuration:

- `// swiftlint:disable` (or `disable:next`, `disable:this`) anywhere;
- `disabled_rules`, `only_rules` or `excluded` in `.swiftlint.yml`;
- relaxing a rule's thresholds to make a violation go away.

`scripts/check-lint-exceptions.sh` enforces this and runs first in CI.

**Fix the code, not the rule.** If a rule genuinely does not fit this project,
do not disable it on your own initiative: say so in the pull request, wait for
the repository owner (@berendkleinhaneveld) to confirm in writing, and record
the approved exception in an ADR. An agent must never introduce an exception
unprompted, and never as a way of getting a red pipeline green.

The same applies to compiler diagnostics: do not silence a warning with
`@available` juggling, a cast, `_ =` or `#warning` suppression when the honest
fix is to change the code.

## Rule 2: builds are warning free

`SWIFT_TREAT_WARNINGS_AS_ERRORS` and `GCC_TREAT_WARNINGS_AS_ERRORS` are `YES` in
the project and are passed again on the CI command line, for the app *and* the
test targets. A new warning is a failed build. Deprecations count: when an API
is deprecated in tvOS 26, migrate to the replacement.

## Rule 3: keep an ADR for important decisions

Architecturally significant decisions are recorded as Architecture Decision
Records in [`docs/adr/`](docs/adr/README.md), one numbered Markdown file per
decision, following Michael Nygard's format (Context, Decision, Alternatives,
Consequences). See [ADR 0001](docs/adr/0001-record-architecture-decisions.md)
for why.

**Write an ADR when** the decision is hard to reverse, or when a future reader
would ask "why is it done this way?":

- adding, replacing or removing a dependency or an Apple framework;
- module, layer or navigation structure, and how state flows through the app;
- persistence, migration and caching (this app uses SwiftData — changing that
  is an ADR, as is a schema migration strategy);
- networking, authentication, error handling and logging approaches;
- testing strategy, or changes to the CI pipeline itself;
- any approved exception to the rules above.

**Do not write one for** a bug fix, a rename, or a view that follows the
patterns already in the code base.

**How:** copy `docs/adr/template.md` to `docs/adr/NNNN-short-title.md` with the
next free number, fill it in, add the row to the index in
`docs/adr/README.md`, and link it from the pull request. ADRs are append-only:
supersede an outdated record with a new one — do not rewrite history. An agent
that is unsure whether a decision is significant should write the ADR and let
the reviewer decide; a decision that turns out to be routine costs one small
file, an undocumented one costs an afternoon later.

## Code style

SwiftLint settles formatting; these are the conventions it cannot check.

- **Naming.** Types are `UpperCamelCase` with no underscores — the module is
  `NPO_light`, but a type is `NPOLightApp`. Follow the Swift API Design
  Guidelines: methods read as phrases at the call site, booleans as assertions
  (`isEmpty`, `hasLoaded`).
- **SwiftUI.** Keep `body` small; extract a subview or a computed property
  instead of nesting a large view tree. Views hold no business logic beyond
  presentation. Every view gets a `#Preview`.
- **SwiftData.** `@Model` types live in `NPO light/`, one type per file. Access
  the context through `@Environment(\.modelContext)`; do not reach for the
  shared container from a view.
- **Concurrency.** UI state is `@MainActor`. Do not add `@unchecked Sendable`
  or `nonisolated(unsafe)` to silence the compiler — model the isolation
  properly.
- **Errors.** No `try!`, no force unwraps (`force_unwrapping` is enforced), no
  implicitly unwrapped optionals. `fatalError` is for genuinely unrecoverable
  programmer error only, and always with a message.
- **Comments** explain *why*. Delete Xcode's generated placeholder comments
  instead of shipping them.

## Tests

- New behaviour comes with a test. A test without an assertion is not a test —
  do not commit an empty `@Test func example() {}` placeholder.
- Unit tests use Swift Testing: `@Test`, `#expect`, `#require`. Name the
  function after the behaviour (`itemKeepsItsTimestamp`), and keep it under 40
  characters — `identifier_name` is enforced in test code too.
- UI tests are slow; add one only for a flow that unit tests cannot cover.
- Never make a test pass by weakening or skipping it. A failing test on your
  branch is a bug in your branch until proven otherwise.

## Working with git

- Branch off `master`; never commit to `master` directly.
- Keep commits focused, with a message that explains the why in the body.
- Fill in the pull request template (`.github/pull_request_template.md`),
  including the ADR and lint-exception checkboxes.
- Do not commit `xcuserdata/`, `build/` or `.xcresult` bundles (see
  `.gitignore`). Do commit changes to the shared scheme.

## What to do when you are stuck

State the problem and stop, rather than working around a rule. Specifically:
if the only way you can see to get CI green is to disable a rule, exclude a
file, skip a test, or suppress a warning, that is a signal to ask the
repository owner — not to proceed.
