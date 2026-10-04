//
//  ScriptedPlayback.swift
//  NPO light
//

#if DEBUG
import AVFoundation

/// A `PlaybackStarting` that plays the test card whatever it is asked for
/// (ADR 0019). It is what plays in previews, in the app as a test launches
/// it, and in any debug build on the simulator, where NPO's protected streams
/// cannot play. Debug builds only.
@MainActor
struct ScriptedPlayback: PlaybackStarting {
    func playback(of playable: Playable, in mode: Mode) async throws -> Playback {
        let item = AVPlayerItem(url: try await TestCard.video())
        return Playback(player: AVPlayer(playerItem: item), keys: nil)
    }
}
#endif
