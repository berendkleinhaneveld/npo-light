## What does this change?

<!-- A short description of the change and, more importantly, why it is needed. -->

## How was it verified?

<!-- Describe the manual checks. The automated checks below are run by CI. -->

- [ ] `./scripts/lint.sh` passes (SwiftLint, strict, no exceptions)
- [ ] `./scripts/build.sh` passes with zero warnings
- [ ] `./scripts/test.sh` passes
- [ ] Tested on the Apple TV simulator

## Architecture decisions

- [ ] This change makes no architecturally significant decision, **or**
- [ ] An ADR was added or updated in `docs/adr/` and is linked here: <!-- docs/adr/000X-....md -->

## Lint or warning exceptions

- [ ] This change adds no `swiftlint:disable` comment, no `disabled_rules`, no
      `excluded` path and no suppressed compiler warning.
- [ ] It does add one, and @berendkleinhaneveld has approved it in this pull
      request. Reason: <!-- explain, and link the ADR that records it -->

> Exceptions to the linting rules are not allowed unless the repository owner
> confirms them first. CI (`scripts/check-lint-exceptions.sh`) fails otherwise.

## Notes for reviewers

<!-- Anything worth calling out: trade-offs, follow-up work, screenshots. -->
