# 1. Record architecture decisions

- **Status:** Accepted
- **Date:** 2026-08-29
- **Deciders:** Berend Klein Haneveld

## Context

NPO light is worked on by a small number of people and, increasingly, by coding
agents. Both forget why a decision was made, and an agent that cannot find the
reasoning tends to re-litigate a settled question or quietly contradict it. Git
history records *what* changed, but the commit that introduces a framework
rarely explains which alternatives were weighed, or why they lost.

## Decision

We keep Architecture Decision Records in `docs/adr/`, one Markdown file per
decision, numbered sequentially and written in the format described by Michael
Nygard in "Documenting Architecture Decisions". Every architecturally
significant decision gets an ADR in the same pull request that implements it,
and the pull request links to it. ADRs are append-only: a decision that no
longer holds is superseded by a new ADR rather than edited away.

## Alternatives considered

- **A single ARCHITECTURE.md** — cheap to start, but it describes only the
  current state. The reasoning and the rejected alternatives get overwritten on
  every edit, which is exactly the part that is expensive to reconstruct.
- **Rely on pull request descriptions** — the reasoning exists but is spread
  across a service, unsearchable from a checkout, and invisible to an agent
  working offline in the repository.
- **No records at all** — the status quo, and the reason this ADR exists.

## Consequences

- A pull request that makes an architecturally significant decision carries one
  extra file, and reviewers are expected to review the reasoning, not just the
  diff.
- `docs/adr/README.md` lists the records and explains when one is required, so
  new contributors and agents can orient themselves from the repository alone.
- Decisions taken before this ADR are undocumented; they are written up
  retroactively only when they are next touched.
