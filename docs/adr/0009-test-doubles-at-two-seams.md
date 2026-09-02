# 0009. Test doubles at two seams, with captured fixtures for the shapes

- **Status:** Accepted
- **Date:** 2026-09-02
- **Deciders:** @berendkleinhaneveld

## Context

[ADR 0008](0008-one-boundary-around-the-npo-backend.md) put one boundary around
the NPO backend and said the protocols "get fakes".
[NFR-MAINT-04](../requirements/nfr-maintainability.md) says the unit suite is
offline and deterministic, and that time comes from an injectable clock. Neither
says what shape a double takes, and the answer is not obvious, because the
boundary has two insides.

**Above** the boundary the app deals in items, episodes and accounts. A double
there answers in those terms, and the tests that use it are about the app's own
behaviour: debounce and cancellation, cache-first rendering, focus, pin
ordering, next-episode selection.

**Below** it — inside the boundary — is everything the recon spikes paid for
([ADR 0007](0007-sign-in-with-the-device-code-grant.md), ADR 0008): a
device-code grant that has to be polled at the interval NPO advertises inside
the window NPO sets; a refresh token that is single-use and rotates, where
reusing one kills the session; a subscription check where only the exact string
`premium` counts; an `Authorization` header that must carry a raw JWT *without*
`Bearer`; and a bearer to the app backend that is the `id_token` and not the
`access_token`, whose failure mode is a partial one that reads like a header
problem. That knowledge is knowledge about bytes on a wire.

One seam cannot hold both. A double at the boundary replaces the whole second
list wholesale: the app would have no test that its poll ever polls, and none
that a spent refresh token is never presented twice. A double at the wire drags
JSON into every view-model test that has no opinion about JSON.

There is a second question underneath: **how much behaviour a double needs**.
Most need none — answer this, and the test is about what the caller does with
the answer. A few need real behaviour, because the requirement is *about* the
behaviour: "exactly one refresh under concurrency" cannot be asserted against
something that does not count, and "the stored token is replaced before it is
used again" cannot be asserted against something that always says yes.

And a third: **where the response shapes come from**. Hand-written JSON drifts
from the real thing silently. Captured JSON does not, but the captures live with
the proof-of-concept that produced them, outside this repository and deliberately
kept there (ADR 0008): they are capture material from a private account.

## Decision

### 1. Two seams, at two depths

**Seam A — the domain boundary.** The protocols from ADR 0008. Everything above
them — view models, stores, the playback coordinator — is tested against doubles
that answer in the app's own types. No JSON above this line, ever.

**Seam B — an HTTP transport, inside the boundary.** The concrete NPO client
takes an `HTTPTransport` rather than reaching for `URLSession`, and tests hand it
canned bytes. This is where the wire-level knowledge above is held to account:
that the poll polls, that the header omits `Bearer`, that an unfamiliar
subscription type reads as free.

Alongside it, two more injected seams that exist for the same reason:
`Clocking`, so nothing sleeps, and `TokenStore`, so nothing touches the
Keychain.

`HTTPTransport` returns a plain `HTTPResponse` value rather than
`HTTPURLResponse`, whose initialiser is failable — building one in a test would
need a force unwrap, which the lint rules do not allow.

### 2. Doubles are closures by default, stateful only where a requirement is about state

The default double takes a closure and does nothing else:

```swift
StubTransport { _ in .json(#"{"error":"authorization_pending"}"#, status: 400) }
```

There is deliberately **no configuration API**. A closure already expresses
every case a test can want — a fixed body, a sequence, a delay on the injected
clock, a throw, a call that never returns — without a vocabulary to learn, and
the interesting behaviour stays written at the point in the test that cares
about it.

Where a requirement is about state, a **fake** with real behaviour earns its
place. There is exactly one at the moment, `FakeIdentityProvider`, modelling
three rules of `id.npo.nl` and nothing else:

1. approval takes time — the poll answers `authorization_pending` until the test
   approves, so a client that does not poll never signs in;
2. refresh tokens rotate and are single-use — presenting a spent one answers
   `invalid_grant`, as NPO does;
3. the code expires — past the window the poll answers `expired_token` rather
   than pending for ever.

Each is a bug the app can really have and a canned response would hide. It is a
fake identity provider, not a fake NPO: the catalogue has no state worth
modelling, so it gets stubs and fixtures.

The clock is a **narrower protocol than the standard library's `Clock`** — a
`now` and a `wait`, which is all the app does with time. `TestClock.wait(for:)`
returns immediately and advances `now`, recording what it was asked for, so a
five-second poll interval is assertable without a five-second test. It cannot
express "the code is still waiting"; nothing needs that yet, and buying it means
continuations and the deadlocks that come with them.

### 3. Fixtures are curated captures, one file per endpoint per outcome

Response bodies live in `NPO lightTests/Fixtures/` as JSON, extracted from the
proof-of-concept's notes and **sanitised** — no real tokens, account identifiers
or personal data — and **minimised** to the fields the app reads, with the
nesting and the types left as they came. A `README.md` beside them records where each came from
and when, and what remains unobserved.

They are snapshots of an unversioned API, not a contract. When NPO changes
something, the fixture is the record of what it used to be, which is most of
their value.

**A shape nobody has captured is not written as a fixture.** The clearest case
is an account without NPO Plus: `Q-08` was answered by decision rather than by
evidence, and a `account-free.json` would be fabricated data wearing the costume
of a capture. Tests for that path build their body inline, where it is visible
that it is invented.

### 4. Requirement identifiers stay out of the test target until a requirement is implemented

`scripts/requirements-coverage.sh` greps the test directories for identifiers,
so an `FR-AUTH-07` in a comment on a shared test double counts as coverage
forever after. Test doubles therefore cite ADRs and describe the rule in words;
the identifiers go in the app target's doc comments, which the script does not
read, and in `@Test` display names when a test actually proves the requirement.

## Alternatives considered

- **One configurable fake backend**, driven by a scenario enum — rejected, and
  it was the obvious first idea. It becomes a second implementation of NPO with
  its own bugs, and its own vocabulary that every test has to learn; tests read
  as `fake.configure(.plusAccountExpiredToken)` and no longer say what they are
  about. It also has no natural stopping point, because "simulate NPO" has none.
  Closures give the same per-test control with no configuration surface at all.
- **`URLProtocol` stubbing**, the usual way to fake `URLSession` — rejected.
  `URLProtocol.registerClass` is process-global mutable state, and Swift Testing
  runs suites in parallel by default, so it buys order-dependent flakes.
  Scoping it per-session through `URLSessionConfiguration.protocolClasses` avoids
  that, but an injected protocol is simpler, needs no `HTTPURLResponse`, and
  lets a test assert on the request that went *out*, which is half of what has
  to be checked here.
- **A local HTTP server for the suite** — rejected. Slow, a dependency, a port
  to contend over, and it makes an offline suite depend on the loopback stack.
- **`swift-clocks` for the test clock** — rejected for now. It is good, and it
  solves a problem this app does not have: two operations do not justify a
  dependency, and a dependency is its own ADR under AGENTS.md Rule 3.
- **Conforming to the standard library's `Clock`** instead of a narrow protocol
  — rejected. A correct conformance means instant advancement, cancellation and
  waker ordering; the app only ever asks what time it is and waits.
- **Hand-written JSON instead of captured fixtures** — rejected as the default.
  It cannot drift from a real response because it was never near one. It stays
  the right choice for a shape nobody has observed, which is what point 3 says.

## Consequences

- **The wire knowledge is testable**, which is the point: the poll interval, the
  rotation, the missing `Bearer` and the `premium` check all have a seam that
  can hold them, without a network and without an NPO account.
- **Two doubles exist for one call chain**, and a new endpoint often means
  touching both — a stub at Seam A for the callers, a fixture at Seam B for the
  client. That is the cost of the split and it is paid on every feature.
- **The suite stays fast and parallel-safe.** Nothing sleeps, nothing registers
  a global, nothing shares a keychain.
- **`KeychainTokenStore` is not covered by any of this.** Every test above it
  uses `InMemoryTokenStore`, so the real store needs its own integration tests,
  with a per-run unique service name so repeat and parallel runs do not collide.
- **Two of FR-AUTH-02's criteria are not unit-testable at all** — that the token
  survives a reboot, and that it is readable on a television nobody has touched
  (`kSecAttrAccessibleAfterFirstUnlock`). The simulator writes to Application
  Support happily, which is the discrepancy ADR 0007 was written around. Those
  are device checks, and the suite passing is not evidence for them.
- **UI tests cannot use any of these doubles**: a UI test drives a separate
  process and cannot inject a Swift protocol into it. The flows that need one —
  parts of FR-AUTH-06 are genuinely visual — will compose a fake from a
  `#if DEBUG` switch on the launch environment. That is deferred until a test
  needs it, and NFR-MAINT-03 pushes most of it down to view models anyway.
- **The fixtures are a second copy of something that changes on NPO's schedule.**
  They will go stale silently, because nothing in CI talks to NPO. That is
  accepted: a stale fixture that documents its capture date is still better
  evidence than an invented one.
