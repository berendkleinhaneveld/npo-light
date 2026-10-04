# 0016. Log at the seams, and keep whole exchanges in files in debug builds

- **Status:** Proposed
- **Date:** 2026-10-04
- **Deciders:** @berendkleinhaneveld

## Context

The app logs nothing. Every failure behind the NPO boundary
([ADR 0008](0008-one-boundary-around-the-npo-backend.md)) ends as one of a few
sentences on a screen, which is what NFR-REL-02 asks for and is of no use to
whoever has to find out why. `BackendError.unreachable` in particular is
designed to forget its cause.

That is about to matter. Playback has never met a real stream
([#13](https://github.com/berendkleinhaneveld/npo-light/pull/13)), the backend
is private and unversioned, and the first real run is on an Apple TV — where
nothing can be inspected that the app did not write down.

Three things were asked for: logging that can be configured, a way to see every
request and response, and something for crashes.

The constraints:

- **NFR-PRIV-02 said no token is logged at any level, in debug or release.**
  A request log with the credentials taken out needs a list of what counts as
  one — two headers, a cookie, and the bodies of three different responses —
  and is wrong the first time NPO adds a fourth. The owner's decision is to be
  practical: these are session credentials on a development television, so a
  debug build may keep them, and a release build may not.
- **The system log cuts a message off at about a kilobyte.** Measured on
  macOS 15 with `Logger`: 900 bytes arrive whole, 2,000 do not. A catalogue
  response is hundreds of kilobytes.
- **An Apple TV launched from its home screen has no launch environment**, and
  the app has no settings screen yet.
- **The video does not pass through the app's transport.** `AVPlayer` fetches
  the manifest and the segments itself.
- **MetricKit's crash diagnostics are unavailable on tvOS** (`API_UNAVAILABLE`
  in the tvOS 26.2 SDK), and NFR-PRIV-03 rules out a crash reporter that sends
  anything off the device.
- The app may never be published. Diagnostics are for debug runs on the
  owner's own television.

## Decision

**We log at the two seams that already exist
([ADR 0009](0009-test-doubles-at-two-seams.md)), by wrapping what is there, and
in a debug build we can keep every exchange with NPO whole, as a file.**

1. **A narrow `Logging` protocol** — a message, a level, a category — with
   `SystemLog` over the unified log (`os.Logger`) in production and a recording
   double in tests. Four categories: `session`, `catalogue`, `playback`,
   `http`.
2. **At the domain boundary, decorators.** `LoggedAuthenticator`,
   `LoggedCatalogue` and `LoggedPlayback` wrap the real implementations in the
   composition root and log every error on its way out. No screen model knows
   about logging, and none of their tests changed. These lines are always on,
   so they name the call and the cause and nothing the user typed or watched by
   title (NFR-DIAG-01).
3. **At the transport, `LoggingTransport`.** It wraps `URLSessionTransport`
   and is steered by `NPO_LIGHT_HTTP_LOG`: `off`, `summary` or `full`
   (NFR-DIAG-02). A request that got no answer is logged whatever the setting,
   with the system's own error.
4. **`full` writes files, not log messages.** One JSON document per exchange
   in `Caches/http-log/`, with headers and bodies as they were, credentials
   included, and the log line naming the file (NFR-DIAG-03). `full` exists only
   in debug builds; elsewhere it is a summary. NFR-PRIV-02 is amended to say
   exactly that.
5. **The player speaks for the video.** `LoggedPlayback` listens to the player
   item it hands out: the error it stops with, and each entry of its error log
   (NFR-DIAG-04).
6. **Nothing is built for crashes.**

### In practice

- **Turn it on:** Product → Scheme → Edit Scheme → Run → Arguments, tick
  `NPO_LIGHT_HTTP_LOG`. It is `full`; change the value for `summary`.
- **Read the log:** the Xcode console while attached. Otherwise Console.app on
  the Mac, with the Apple TV selected and the filter
  `subsystem:com.bearduck.NPO-light`; switch on *Include Info Messages* to see
  summaries.
- **Read the files:** on a simulator, the directory is logged at launch. From
  a television:

  ```sh
  xcrun devicectl device copy from --device "<name>" \
    --domain-type appDataContainer --domain-identifier com.bearduck.NPO-light \
    --source Library/Caches/http-log --destination ./http-log
  ```

- **A crash, attached:** the debugger stops on the line.
- **A crash, not attached:** Xcode → Window → Devices and Simulators → the
  Apple TV → Open Recent Logs, or the same `devicectl` command with
  `--domain-type systemCrashLogs`. The error-level lines from point 2 are in
  the device's log from the seconds before it.

## Alternatives considered

- **Redact credentials and log the rest** — what NFR-PRIV-02 originally
  implied. Rejected by the owner as more machinery than the risk deserves: the
  credentials are temporary, the builds are debug builds, and a redaction list
  is a second thing to keep in step with NPO.
- **Bodies as log messages, cut into numbered pieces** — built first, and it
  worked. Rejected once files were on the table: a 300 KB response is four
  hundred lines to reassemble by hand, where a file is a file.
- **Logging inside the screen models** — rejected. Five initialisers, every
  preview and every model test would take a parameter that has nothing to do
  with what they are about. The decorators see the same errors one layer down.
- **Calling `Logger` directly wherever something fails** — rejected. It cannot
  be asserted on, and "this line never carries a search term" is a requirement
  that wants a test. The cost is that Xcode's jump-to-source points at
  `SystemLog`, and that the system's per-value privacy marking is not used:
  every line is public, and what may be in one is decided where it is written.
- **A switch in the app's settings** — deferred, not rejected. It would work
  without Xcode, but it is a setting no requirement asks for, on a screen that
  does not exist.
- **A proxy on the network** instead of anything in the app — it is how the
  captures were made, and it stays the right tool for watching NPO's own app.
  For this app it means certificates on the television for something the
  transport seam gives for free.
- **A third-party crash reporter** — ruled out by NFR-PRIV-03.
- **MetricKit** — not available on tvOS.
- **Catching signals or uncaught exceptions to write a last log line** —
  rejected. It is unreliable in exactly the states a crash leaves behind, a
  Swift trap is not an exception, and the system's report is better than
  anything the app could write.

## Consequences

- **A failure on the television can be read afterwards**: which call, what
  status, what the system said — and in `full`, the bytes.
- **A debug build with `full` writes live credentials to disk**, among them the
  refresh token, which is the long-lived one. They sit in the app's `Caches` on
  a development device and in whatever folder they are copied to on the Mac.
  That folder is the thing to be careful with: it does not belong in a commit,
  an issue or a chat. Fixtures made from these files are sanitised as ADR 0009
  already says.
- **The `http` category does not see the video.** A stream that fails shows up
  under `playback`, in the player's words, and that part has only been tested
  against a file that does not exist.
- **Request logging needs a launch from Xcode.** A failure that only happens on
  an ordinary evening leaves the always-on error lines and nothing more.
- **Copying files off an Apple TV with `devicectl` has not been tried.** The
  command exists and takes these arguments; whether tvOS serves an app's
  container to it is the first thing the first run will show. If it does not,
  the fallback is the summary lines, or bringing back log pieces for bodies.
- **The files are capped at 500**, tidied at launch, and tvOS may empty
  `Caches` by itself (ADR 0015). Both are fine: they are read once.
- **Reversing it is cheap.** Three decorators and a wrapper, all named in one
  function of the composition root.
