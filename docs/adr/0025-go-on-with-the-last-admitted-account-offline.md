# 0025. Go on with the last admitted account when NPO cannot be asked

- **Status:** Proposed
- **Date:** 2026-10-05
- **Deciders:** @berendkleinhaneveld

## Context

At every launch the app asks NPO about the account behind the stored session,
because the subscription is checked every time and not only at sign-in
(FR-AUTH-08). When NPO could not be reached, the launch ended on a page that
said so and offered a retry.

NFR-REL-01 asks for more: without a network the app still shows what it
knows. And it knows a good deal. The home page is drawn from what is kept on
the television ([ADR 0015](0015-local-data-in-two-places.md)), and a page seen
before opens from what NPO answered then
([ADR 0024](0024-keep-what-npo-answered-and-ask-again-behind-it.md)). The one
thing in the way is the question about the account.

FR-AUTH-08 also says that an unreachable backend is not evidence about the
account. That cuts both ways: it is no reason to sign anybody out, and no
reason to keep a family that was admitted yesterday away from its own lists.

## Decision

**The account NPO last admitted is remembered, and a launch that cannot ask
goes on with it.** Its identifier is kept in `UserDefaults` when NPO admits
it — only ever an account with NPO Plus — and forgotten at sign-out, when NPO
says the session has ended, and when NPO says the account has no Plus any
more. A launch that cannot reach NPO and finds one shows the home page, marked
as offline; one that finds none shows the problem page with its retry, as
before.

**While offline, NPO is asked again every thirty seconds**, through the
injected clock. The first answer is acted on as at any launch: the notice
goes, a lapsed subscription is told, an ended session returns to sign-in.

**The home page says so.** A notice, for as long as it lasts, says that NPO
cannot be reached and that playing and searching have to wait. The pages
themselves already explain a request that failed.

**The session stays in the Keychain.** What is remembered is an identifier
and nothing that signs anybody in (NFR-PRIV-02).

## Alternatives considered

- **Keep the problem page.** Honest, and it keeps the subscription check
  absolute. But it turns a router that is slow to come up into an app that
  shows nothing, while everything the home page needs is on the television.
- **Trust the stored session without asking, and check behind the home page.**
  Faster at every launch, not only an offline one. Rejected for now: an
  account without Plus would see the home page before it is turned away,
  which FR-AUTH-08 rules out in so many words.
- **Watch the network with `NWPathMonitor` instead of asking again on a
  timer.** It answers at once when the network returns, but a network is not
  NPO: a path that is up says nothing about whether NPO answers. Another
  framework for a second's difference.
- **Let the remembered answer lapse after a while.** Offline nothing plays, so
  there is nothing for a lapsed subscription to reach; and the first answer
  from NPO is acted on.

## Consequences

- An account whose Plus ended can still see its lists while NPO is
  unreachable. It cannot play anything: a stream needs NPO.
- If the account endpoint alone is down while streams are served, the app
  plays on yesterday's answer about the subscription until the endpoint is
  back, at most thirty seconds after it answers again.
- Kids mode cannot be switched to while offline: whether the account has a
  kids profile is still asked of NPO. The mode the app was last in is kept.
- A request every thirty seconds while offline, and none otherwise.
