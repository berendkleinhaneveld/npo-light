# Playback

Playing, resuming, moving on to the next episode, and knowing when to stop.
Prefix `FR-PLAY`.

## FR-PLAY-01 — Playing uses the system player

- **Status:** Accepted

Playback uses the standard tvOS player, with the transport controls, subtitle
and audio-track selection that tvOS provides.

**Acceptance criteria**

- Play, pause, scrub, skip and the info panel behave as they do in any tvOS
  app.
- Subtitles and audio tracks the stream carries are selectable through the
  system UI.
- The app adds no custom transport controls that shadow the system ones.

## FR-PLAY-02 — Resume where you stopped

- **Status:** Accepted

An item with a stored position resumes there. One without starts at the
beginning.

**Acceptance criteria**

- Stopping halfway and playing again resumes within a second of where playback
  stopped.
- An item watched past the completion threshold (FR-PLAY-04) starts from the
  beginning when it is played again deliberately.
- Positions are stored per mode (FR-MODE-05).

## FR-PLAY-03 — Positions are persisted, not lost

- **Status:** Accepted

The playback position is written to the local store regularly during playback
and when playback ends, so that killing the app or losing power costs seconds,
not the whole episode.

**Acceptance criteria**

- The position is persisted at a fixed interval during playback.
- The position is persisted when playback pauses, stops, or the app goes to the
  background.
- After a crash or a force quit, the resume point is no more than that interval
  behind where playback actually was.

## FR-PLAY-04 — "Finished" has one definition

- **Status:** Accepted

An episode counts as finished once playback passes **the later of 95% of its
duration and the point where 90 seconds remain**. Everything that depends on
"watched" — the next-episode logic, the tiles, autoplay — uses that one
definition.

**Rationale.** A percentage alone is too strict for a long episode with several
minutes of credits; a fixed number of seconds alone is too lenient for a short
children's episode. Taking the later of the two lets the percentage govern
short items and the fixed remainder govern long ones. The value is a starting
point, chosen to be adjusted once the family has lived with it
([Q-04](open-questions.md#q-04--what-counts-as-near-the-end)).

**Acceptance criteria**

- The threshold is one named constant, not a number repeated across the code.
- A 60-minute episode is finished at 58:30; a 10-minute episode at 9:30.
- An episode shorter than 90 seconds is finished at 95% of its duration — the
  rule never resolves to a negative position.
- An episode of unknown duration is finished only by playback actually reaching
  its end.
- Passing the threshold marks the episode watched, whether playback then
  stopped or ran to the very end.
- Stopping just before the threshold leaves the episode unwatched, with its
  position.

## FR-PLAY-05 — Autoplay in normal mode

- **Status:** Accepted

In normal mode, finishing an episode of a series plays the next one straight
away.

**Acceptance criteria**

- The next episode starts without the user pressing anything.
- An overlay names the next episode and offers to stop, for long enough to be
  used.
- Choosing to stop returns to where playback was started from, not to a dead
  screen.

## FR-PLAY-06 — Autoplay in kids mode pauses first

- **Status:** Accepted

In kids mode, the next episode is preceded by a deliberate pause — five seconds
by default, configurable (FR-SET-02).

**Rationale.** A gap gives a child, or the adult in the room, a moment to stop
before the next episode carries them along.

**Acceptance criteria**

- The pause shows a visible countdown that a child can understand.
- Pressing stop during the countdown ends the session instead of continuing.
- The countdown length comes from settings, and a changed setting takes effect
  on the next episode boundary.
- A pause of zero means autoplay behaves as in normal mode.

## FR-PLAY-07 — Autoplay knows when to stop

- **Status:** Accepted

Autoplay only continues within a series, and stops when there is nothing to
continue to.

**Acceptance criteria**

- The last episode of a series ends the session rather than starting something
  unrelated.
- The end of a season continues into the next season when one exists
  (FR-CONTENT-02).
- A film or a standalone episode never autoplays into anything.
- An unavailable next episode is skipped (FR-CONTENT-05).

## FR-PLAY-08 — Are you still watching?

- **Status:** Accepted

After a stretch of continuous playback the app asks whether anyone is still
there: one hour in kids mode, three hours in normal mode, both configurable
(FR-SET-02).

**Acceptance criteria**

- The timer counts continuous playback across episode boundaries; autoplay does
  not reset it.
- Any remote interaction — pause, scrub, a button press — resets the timer.
- The prompt pauses playback and offers to continue.
- With no answer within a defined grace period, playback stops and the app
  returns to home.
- Confirming continues from exactly where the prompt interrupted, and restarts
  the timer.
- The two durations are independent: changing one does not change the other.

## FR-PLAY-09 — Watching updates the home page

- **Status:** Accepted

Playing something is what fills the recently watched row (FR-HOME-06).

**Acceptance criteria**

- Starting playback records the item as most recently watched, per mode.
- A series records once, updated per episode, rather than one entry per
  episode.
- Finishing an episode leaves the item pointing at the next one (FR-HOME-07).

## FR-PLAY-10 — Playback errors are recoverable

- **Status:** Accepted

A stream that will not play says why and offers a way forward.

**Acceptance criteria**

- A failure to start playback shows a message and a retry, not a black screen.
- A failure mid-playback keeps the stored position, so retrying resumes rather
  than restarts.
- An expired session during playback refreshes and retries once before giving
  up (FR-AUTH-03).
- An item that is no longer available says so (FR-CONTENT-05).
