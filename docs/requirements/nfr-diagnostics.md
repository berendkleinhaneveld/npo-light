# Diagnostics

Prefix `NFR-DIAG`. The backend is private and undocumented, and the first place
this app meets it for real is a television in a living room. When something
fails there, the app has to have left an account of it
([ADR 0016](../adr/0016-log-at-the-seams.md)).

This is for the person building the app, not for the family using it: nothing
here puts anything on screen.

## NFR-DIAG-01 — A failure leaves a trace

- **Status:** Implemented

Every call across the NPO boundary that fails is written to the system log
with which call it was and what the cause was, before it becomes a sentence on
a screen (NFR-REL-02). This is always on, in every build, and so it is written
to be safe to leave on.

**Acceptance criteria**

- A failed sign-in, catalogue or playback call is logged at error level, under
  a category for its area, naming the call and the underlying error.
- A request that got no answer at all is logged with its method, host, path and
  the system's own error — the cause that "NPO could not be reached" hides.
- These lines carry no header, no body, no token and no search term.
- A call that was cancelled because its screen went away is not logged as a
  failure, and a call that succeeds leaves nothing.

## NFR-DIAG-02 — Request logging is switched on per launch

- **Status:** Implemented

How much is kept of each request to NPO is chosen when the app is launched,
with the environment variable `NPO_LIGHT_HTTP_LOG`:

| Value | What is kept |
| --- | --- |
| `off`, or nothing | Only what NFR-DIAG-01 asks for. |
| `summary` | One log line per request: method, address without its query values, status, size and duration. |
| `full` | The summary, and the whole exchange in a file (NFR-DIAG-03). |

**Acceptance criteria**

- Without the variable, and with a value that is not one of these, nothing
  beyond NFR-DIAG-01 is kept.
- A summary line carries no header, no body and no query value: the names of
  the query's parameters are there and what they were set to is not. NPO signs
  a licence address by putting the authorisation in its query.
- Logging changes neither the request that goes out nor the response that
  comes back.
- The shared Xcode scheme carries the variable, switched off, so that turning
  it on is one tick.

A launch from the television's home screen has no environment, so this is a
switch for a run from Xcode. A switch on the television itself would be a
setting, and FR-SET does not ask for one.

## NFR-DIAG-03 — A debug build can keep whole requests and responses

- **Status:** Implemented

With `full`, every request and its response is written to a file of its own:
method, address, headers and body in both directions, exactly as sent and
received. **That includes credentials** — session tokens, the player token and
the licence credential — because an exchange with the interesting part removed
is not what was sent. A release build never does this (NFR-PRIV-02).

**Acceptance criteria**

- Each exchange is one JSON file under `Caches/http-log/`, named so that the
  files sort by time and say what they hold: the time, a running number, the
  method, the end of the path and the status.
- A JSON body is nested in the file as JSON, other text is a string, and a
  body that is not text — a key request, a licence — is base64.
- A request that got no answer is kept too, with the error in place of a
  response.
- The log line for the request names the file.
- In a build that is not a debug build, `full` behaves as `summary`: no file is
  written and no header or body is kept anywhere.
- A launch that keeps files first removes the oldest beyond a fixed ceiling,
  and logs where the directory is.

## NFR-DIAG-04 — The player's own errors are logged

- **Status:** Implemented

The video does not pass through the app: the system player fetches the
manifest, the segments and — by way of the app — the keys. What it reports
about a stream is therefore logged as it is reported: the error a stream
stopped with, and each entry the player adds to its error log while playing.

**Acceptance criteria**

- A stream the player gives up on is logged at error level with the item, the
  mode and the player's error, including the error underneath it.
- Each new entry in the player's error log is logged with its domain, status
  code, comment and the host it came from — not the full address, which names
  a signed stream.
- Listening lasts as long as the playback does and ends with it.

*The first criterion is tested against a stream that does not exist. An
error-log entry cannot be made in a test; the second was seen on an Apple TV on
2026-10-04, when the player reported a segment over its variant's bandwidth
while it went on playing.*

## Crashes

There is no requirement here, on purpose. An app cannot catch its own crash in
any way worth trusting, a crash reporter that sends reports somewhere is ruled
out by NFR-PRIV-03, and Apple's in-app crash diagnostics (MetricKit) are not
available on tvOS. What there is, is what the system keeps: the debugger when
the app runs from Xcode, and the television's own crash log when it does not.
[ADR 0016](../adr/0016-log-at-the-seams.md) says how to read both.
