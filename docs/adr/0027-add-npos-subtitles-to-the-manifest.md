# 0027. Add NPO's subtitles to the manifest the player is given

- **Status:** Proposed
- **Date:** 2026-10-05
- **Deciders:** @berendkleinhaneveld

## Context

FR-PLAY-01 asks that subtitles are selectable through the system's own
player. They were not there at all. NPO does have them, for nearly
everything, but not in the stream: the answer that carries the manifest's
address also names one WebVTT file for the whole programme, and the manifest
itself names sound and picture and nothing else. NPO's own player draws the
file over the video. The system player offers only what the manifest names.

What NPO sends was looked at for three programmes: an HLS stream of
MPEG-TS segments whose timestamps start at zero, every address in the
manifest relative to the manifest, and a plain WebVTT file with times from
the start of the programme.

## Decision

**The player is given NPO's manifest with the subtitles added to it.** When a
stream comes with subtitles, the player is handed an address only the app can
answer, and an `AVAssetResourceLoaderDelegate` — `ManifestLoader` — answers
it with NPO's manifest, fetched then, to which `SubtitledManifest` has added:

- a subtitle rendition for each file, and the group on every variant;
- every relative address written in full, since the manifest is no longer
  where NPO put it.

The rendition points at a playlist the app also answers: one segment, the
file itself at NPO's address, as long as the programme. The picture, the
sound, the keys and the subtitle file are fetched from NPO by the player, as
before.

**The subtitles are offered, not switched on.** Whether they show is the
viewer's choice in the system's menu and the system's settings.

**Without subtitles, or without a length, nothing changes.** The player is
given NPO's address as it was.

## Alternatives considered

- **Draw the subtitles in the app, over the player.** That is what NPO's
  player does. It means parsing WebVTT, timing and styling cues, a menu of
  the app's own — and none of the system's settings for size, colour and
  when subtitles show would apply. It is the custom control FR-PLAY-01 rules
  out.
- **An `AVMutableComposition` of the stream and the subtitle file.** A
  composition cannot hold an HLS stream.
- **Ask NPO for a stream profile that carries subtitles.** None is known,
  and NPO's own apps use the file.
- **Re-time the file to the stream.** Not needed: both start at zero. If NPO
  ever sends a stream that does not, the file needs an `X-TIMESTAMP-MAP`
  and would have to be answered by the app as well.

## Consequences

- Subtitles are in the system player's menu, follow the system's settings,
  and need no code of the app's while something plays.
- The manifest is fetched by the app and not by the player, so a manifest
  NPO refuses is an error from the loader. The player fails with it and the
  screen offers its retry, as for any other failure (FR-PLAY-10).
- The app now reads NPO's manifest, lightly: tags it does not know are
  passed on as they are, and only a `URI` attribute and a line that is an
  address are touched. A change in how NPO writes its manifest can break
  playback of everything that has subtitles, where before the app did not
  look at it.
- It was seen to work on an Apple TV, with a protected stream: the picture
  plays, *Nederlands* is offered, and the subtitles are in step. The
  simulator plays the test card and never comes here (ADR 0019).
- The subtitles are NPO's for the deaf and hard of hearing, and are offered
  under the name NPO gives them. They are not marked as such for the system.
