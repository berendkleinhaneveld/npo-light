//
//  PlayerModel.swift
//  NPO light
//

import AVFoundation
import Foundation
import Observation

/// One playback: getting a stream, playing it, and what to say when that does
/// not work (FR-PLAY-10).
@MainActor
@Observable
final class PlayerModel {
    enum Problem: Equatable {
        /// NPO no longer has the item (FR-CONTENT-05).
        case unavailable

        /// NPO could not be reached.
        case unreachable

        /// The stream could not be started, or stopped playing.
        case failed
    }

    enum State {
        case preparing
        case playing(Playback)
        case failed(Problem)
    }

    let playable: Playable
    let mode: Mode

    private(set) var state = State.preparing

    private let starter: any PlaybackStarting
    private var itemStatus: NSKeyValueObservation?

    init(playable: Playable, mode: Mode, starter: any PlaybackStarting) {
        self.playable = playable
        self.mode = mode
        self.starter = starter
    }

    /// The problem on screen, if there is one.
    var problem: Problem? {
        if case .failed(let problem) = state { return problem }
        return nil
    }

    /// Fetches stream details and starts playing. Called when the player
    /// appears and again on a retry, and each call fetches its own details:
    /// what an earlier attempt was given has expired by then (FR-PLAY-11).
    func start() async {
        itemStatus = nil
        state = .preparing
        do {
            let playback = try await starter.playback(of: playable, in: mode)
            watch(playback.player)
            state = .playing(playback)
            playback.player.play()
        } catch is CancellationError {
            // The player was closed while it was still preparing.
        } catch BackendError.itemUnavailable {
            state = .failed(.unavailable)
        } catch BackendError.unreachable {
            state = .failed(.unreachable)
        } catch {
            state = .failed(.failed)
        }
    }

    /// The player was closed.
    func stop() {
        itemStatus = nil
        if case .playing(let playback) = state {
            playback.player.pause()
        }
    }

    /// A stream that stops being playable — a licence that could not be
    /// obtained, a manifest that would not load — becomes a problem with a
    /// retry rather than a black screen.
    private func watch(_ player: AVPlayer) {
        itemStatus = player.currentItem?.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in
                self?.playbackFailed()
            }
        }
    }

    private func playbackFailed() {
        itemStatus = nil
        state = .failed(.failed)
    }
}
