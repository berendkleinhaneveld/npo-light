## What does this change?

<!-- A short description of the change and, more importantly, why it is needed. -->

## Requirements

<!--
Which requirements in docs/requirements/ does this touch? Name the identifiers,
so the specification and the code stay in step (ADR 0003). Delete the lines
that do not apply.
-->

- **Implements:** <!-- FR-SEARCH-03 — status flipped to Implemented in this PR, named by the test that proves it -->
- **Adds or changes:** <!-- FR-HOME-07 — new, agreed with @berendkleinhaneveld beforehand -->
- **No requirement is affected:** <!-- a bug fix, a rename, a refactor, a change to the tooling -->

<!--
Behaviour that no requirement asks for needs a requirement first: add it here
and say so, rather than widening the app quietly. If a requirement turned out
to be ambiguous, say that too — the answer belongs in the document either way.
-->

## How was it verified?

<!--
Describe the manual checks: what you ran, what you looked at, and what you
could not check.

Tick a box only if you actually ran it on this branch. If you could not run
one — no macOS, no Xcode, no simulator — leave it unticked and say so below.
An unticked box with a reason is fine; a ticked box that was never run is not.
CI is the authority either way.

`./scripts/build.sh` is not listed: it is the quicker loop while iterating
locally, and `test.sh` compiles the same code with the same
warnings-as-errors settings.
-->

- [ ] `./scripts/lint.sh` — SwiftLint, strict, no exceptions (runs on Linux too)
- [ ] `./scripts/requirements-coverage.sh` — requirements and tests still line up (runs on Linux too)
- [ ] `./scripts/test.sh` — builds warning free, then runs the unit and UI tests (needs Xcode)
- [ ] Tested on the Apple TV simulator

**Not run here, because:** <!-- e.g. no macOS in this session. Delete this line if everything above is ticked. -->

## Decisions and exceptions

- [ ] This change makes no architecturally significant decision, **or**
- [ ] An ADR was added or updated in `docs/adr/` and is linked here: <!-- docs/adr/000X-....md -->

- [ ] This change adds no lint exception, no suppressed warning, and no skipped
      or weakened test.

<!--
If it does add one, it needs @berendkleinhaneveld's written approval and an
ADR (AGENTS.md, rule 1). Say what and why here, and wait for that approval — a
green pipeline is not approval.
-->

## Notes for reviewers

<!--
Anything worth calling out: trade-offs, follow-up work, screenshots, and above
all the things you would rather have questioned than nodded through.
-->
