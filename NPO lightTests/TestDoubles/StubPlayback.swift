//
//  StubPlayback.swift
//  NPO lightTests
//

import AVFoundation
@testable import NPO_light

/// A `PlaybackStarting` that answers from a closure and counts its calls, in
/// the app's own types (ADR 0009). The players it hands out have nothing
/// loaded.
@MainActor
final class StubPlayback: PlaybackStarting {
    private let start: (Playable, Mode) async throws -> Void
    private(set) var requests: [(playable: Playable, mode: Mode)] = []

    init(start: @escaping (Playable, Mode) async throws -> Void = { _, _ in }) {
        self.start = start
    }

    func playback(of playable: Playable, in mode: Mode) async throws -> Playback {
        requests.append((playable, mode))
        try await start(playable, mode)
        return Playback(player: AVPlayer(), keys: nil)
    }
}
