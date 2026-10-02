# 0010. Publish an interactive wireframe, drawn from the requirements

- **Status:** Proposed
- **Date:** 2026-09-24
- **Deciders:** @berendkleinhaneveld

## Context

The specification of NPO light is text: some ninety requirements in
[`docs/requirements/`](../requirements/README.md), each with acceptance
criteria. Text is what the tests are written against, and it stays that way
([ADR 0003](0003-track-requirements-in-the-repository.md)). But much of what
the requirements describe is felt rather than read: which way focus moves
after a tile is removed, whether a pinned series tile reads well when it names
the next episode, how a five-second countdown looks to a child, what the home
page is like with two rows instead of three. A reviewer of the requirements
cannot try any of that, and nobody can try the app itself without a Mac,
Xcode and a simulator, or an Apple TV.

Asking for such a tool is also asking where it lives. A design file elsewhere
drifts from the requirements the moment one of them changes, and nobody can
link a requirement to it.

## Decision

We keep an interactive wireframe in the repository, under
[`wireframe/`](../../wireframe/README.md), and publish it to GitHub Pages from
`master`.

- It is plain HTML, CSS and JavaScript with no build step and no dependency
  beyond web fonts, so it opens from any static server and needs nothing
  installed.
- It draws the television at tvOS's 1920×1080 and is driven by the keyboard or
  an on-screen remote, so focus behaviour can be tried rather than imagined.
- Every focusable element names the requirement identifiers it illustrates.
  `scripts/build-wireframe.sh` reads the titles and statuses from
  `docs/requirements/` when the site is assembled, so the panel beside the
  television always shows the requirements as they stand.
- A separate workflow, `.github/workflows/wireframe.yml`, assembles the site on
  pull requests that touch it and deploys it on pushes to `master`. It does
  not touch the three CI jobs of
  [ADR 0002](0002-strict-linting-and-warning-free-builds.md).

**The wireframe is not the specification.** Where it and the requirements
disagree, the requirements win and the wireframe is the bug. It is also not a
source of requirements: a detail it settles that no requirement does — a label,
a timing, where a button sits — is a proposal until a requirement says so.

## Alternatives considered

- **A design tool (Figma or similar)** — rejected. It lives outside the
  repository, cannot read the requirements, and drifts silently; clickable
  prototypes there model focus-driven navigation poorly.
- **SwiftUI previews and screenshots** — rejected as the answer to this
  problem, though the app will have them anyway (every view gets a `#Preview`).
  They need Xcode to see, show one state at a time, and exist only once the
  view has been built, which is too late to question the requirement behind it.
- **Static mock-ups in the requirements** — rejected. Images cannot show focus,
  timing or state changes, and they go stale without anything noticing.
- **A framework (React, a bundler)** — rejected. It would add a toolchain and a
  lockfile to an iOS repository for a page that fits in a few files.

## Consequences

- There is one link that anybody can open to try the app's intended behaviour
  in a browser, on a desk or a phone.
- Changing a requirement that the wireframe illustrates leaves the wireframe
  out of date until someone updates it. That is accepted: the panel reads
  titles and statuses live, and a stale sketch is cheaper than no sketch. It is
  not enforced by CI.
- The repository gains JavaScript that SwiftLint does not see. It is kept small
  and dependency-free so that it needs no linter of its own; if it grows, that
  is a new decision.
- GitHub Pages has to be enabled for the repository once, with *GitHub Actions*
  as its source (Settings → Pages). Until then the deploy job fails and nothing
  else is affected.
- Reversing this means deleting `wireframe/`, the build script and the
  workflow, and switching Pages off.
