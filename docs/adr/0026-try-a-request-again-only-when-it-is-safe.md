# 0026. Try a request again only when it is safe, and only a few times

- **Status:** Proposed
- **Date:** 2026-10-05
- **Deciders:** @berendkleinhaneveld

## Context

NFR-REL-03 asks that requests time out, that transient failures are retried
with backoff, and that permanent ones are not retried in a loop. The timeout
was there: fifteen seconds on the session. Nothing was tried again, so a
connection dropped for a moment — a television waking up, a router handing out
a new address — became a page with a retry button.

Trying again is not free of risk here. NPO's refresh tokens are single-use
([ADR 0007](0007-sign-in-with-the-device-code-grant.md)): a renewal that
reached NPO and whose answer was lost has spent the token, and sending it
again ends the session.

## Decision

**A decorator around the transport tries a request again: `RetryingTransport`,
below the NPO boundary and above the log**, so that every attempt is logged
([ADR 0016](0016-log-at-the-seams.md)).

**Only a `GET` is tried again.** It asks and changes nothing. Everything that
is posted — a renewal, a sign-in poll, a licence request — is sent once, and
its own caller decides what a failure means.

**Only what may pass by itself is tried again:** a connection that was lost or
could not be made, a name that could not be found, and a gateway that answers
502, 503 or 504. Not a timeout, which has had fifteen seconds already; not a
television that knows it has no network; and no other status, least of all a
4xx, which says the request is wrong and will be wrong again.

**Three attempts at most, half a second and then a second and a half apart**,
waited through the injected clock. The last attempt's outcome is handed on as
it is.

## Alternatives considered

- **Let `URLSession` wait for connectivity.** It holds a request until the
  network is back, which on a television without one is a spinner — what
  NFR-REL-02 forbids.
- **Retry in each screen model.** Every model would repeat the rule about what
  is safe, and one of them would get it wrong.
- **Retry everything, the posts too.** One lost answer to a renewal would sign
  the family out, which needs a second device to undo.
- **Retry a timeout.** Three times fifteen seconds before a page says anything
  is a hung app by any other name.

## Consequences

- A failure that passes within two seconds is never seen.
- A page takes up to two seconds longer to say that something is wrong, when
  the failure is one that might have passed.
- The retry a 401 gets after a renewal is not this one: that is one retry,
  decided by the authenticator, and stays there (FR-AUTH-03).
- The rule lives in one place, and a test names each case.
