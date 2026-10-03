//
//  ScriptedPlayback.swift
//  NPO light
//

#if DEBUG
import AVFoundation

/// A `PlaybackStarting` with nothing to play, for previews and for the app
/// when a test launches it (ADR 0009). Debug builds only.
@MainActor
struct ScriptedPlayback: PlaybackStarting {
    func playback(of playable: Playable, in mode: Mode) async throws -> Playback {
        Playback(player: AVPlayer(), keys: nil)
    }
}
#endif
