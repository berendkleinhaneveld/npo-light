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

    /// What whoever started it knew about it.
    let origin: PlayOrigin
    let mode: Mode

    private(set) var state = State.preparing

    private let starter: any PlaybackStarting
    private let positions: PlaybackCoordinator
    private var itemStatus: NSKeyValueObservation?
    private var pauses: NSKeyValueObservation?
    private var ticks: (player: AVPlayer, token: Any)?
    private var ending: (any NSObjectProtocol)?

    /// The latest write of the position, while it is under way.
    private(set) var writing: Task<Void, Never>?

    init(playable: Playable,
         origin: PlayOrigin = .unknown,
         mode: Mode,
         starter: any PlaybackStarting,
         positions: PlaybackCoordinator) {
        self.playable = playable
        self.origin = origin
        self.mode = mode
        self.starter = starter
        self.positions = positions
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
        stopWatching()
        state = .preparing
        do {
            let playback = try await starter.playback(of: playable, in: mode)
            await resume(playback.player)
            await positions.started(playable, from: origin, in: mode)
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

    /// The player was closed, and what it had to write is written: whoever
    /// reads positions after this sees where playback stopped.
    func close() async {
        stop()
        await writing?.value
    }

    /// The player was closed.
    func stop() {
        rest()
        stopWatching()
        if case .playing(let playback) = state {
            playback.player.pause()
        }
    }

    /// Playback stops here for now — closed, paused, or the app left the
    /// screen: the position is written where it will still be after the
    /// television was switched off (FR-PLAY-03).
    func rest() {
        record(resting: true)
    }

    /// Moves a player to the stored position before it starts, so that what
    /// was stopped halfway carries on from there (FR-PLAY-02).
    private func resume(_ player: AVPlayer) async {
        guard player.currentItem != nil,
              let point = await positions.resumePoint(of: playable.id, in: mode) else { return }
        await player.seek(to: CMTime(seconds: point, preferredTimescale: 600))
    }

    /// Hands the player's position to the coordinator, which decides what it
    /// means. The task holds what it needs and not the model: the last write
    /// is made as the player closes.
    private func record(resting: Bool) {
        guard case .playing(let playback) = state, let item = playback.player.currentItem else { return }
        let position = playback.player.currentTime().seconds
        let duration = item.duration.seconds
        writing = Task { [positions, id = playable.id, origin, mode] in
            await positions.played(id, from: origin, to: position, of: duration, in: mode, resting: resting)
        }
    }

    private func stopWatching() {
        itemStatus = nil
        pauses = nil
        if let ticks {
            ticks.player.removeTimeObserver(ticks.token)
        }
        ticks = nil
        if let ending {
            NotificationCenter.default.removeObserver(ending)
        }
        ending = nil
    }

    /// A stream that stops being playable — a licence that could not be
    /// obtained, a manifest that would not load — becomes a problem with a
    /// retry rather than a black screen.
    ///
    /// While it plays its position is written at a fixed interval, at every
    /// pause, and when it reaches the end (FR-PLAY-03).
    private func watch(_ player: AVPlayer) {
        itemStatus = player.currentItem?.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in
                self?.playbackFailed()
            }
        }
        pauses = player.observe(\.timeControlStatus) { [weak self] player, _ in
            guard player.timeControlStatus == .paused else { return }
            Task { @MainActor [weak self] in
                self?.rest()
            }
        }
        let interval = CMTime(seconds: PlaybackCoordinator.interval, preferredTimescale: 600)
        let token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.record(resting: false)
            }
        }
        ticks = (player, token)
        ending = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                        object: player.currentItem,
                                                        queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playedToEnd()
            }
        }
    }

    private func playedToEnd() {
        writing = Task { [positions, id = playable.id, origin, mode] in
            await positions.playedToEnd(id, from: origin, in: mode)
        }
    }

    /// The position survives the failure, so that a retry carries on from
    /// where the stream stopped (FR-PLAY-10).
    private func playbackFailed() {
        rest()
        stopWatching()
        state = .failed(.failed)
    }
}
