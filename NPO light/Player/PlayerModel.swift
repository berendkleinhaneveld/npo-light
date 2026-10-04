//
//  PlayerModel.swift
//  NPO light
//

import AVFoundation
import Foundation
import Observation

/// One sitting at the player: getting a stream, playing it, what to say when
/// that does not work (FR-PLAY-10), and going on to the next episode when one
/// ends (FR-PLAY-05, FR-PLAY-07).
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

        /// Kids mode waits before the next episode, and counts the seconds
        /// down (FR-PLAY-06).
        case pausing(before: Playable, remaining: Int)
        case failed(Problem)
    }

    /// How long the player says that the next episode started by itself,
    /// and offers to stop: long enough to find the remote (FR-PLAY-05).
    static let announcementTime = Duration.seconds(10)

    /// What is playing: what was asked for, and after it the episodes that
    /// followed by themselves.
    private(set) var playable: Playable

    /// What whoever started it knew about it.
    private(set) var origin: PlayOrigin
    let mode: Mode

    private(set) var state = State.preparing

    /// The episode that started by itself a moment ago, while the player
    /// says so (FR-PLAY-05).
    private(set) var announced: Playable?

    /// The sitting is over, and the player is to go away: the last episode
    /// ended, or somebody stopped it from going on (FR-PLAY-07).
    private(set) var isOver = false

    private let starter: any PlaybackStarting
    private let positions: PlaybackCoordinator
    private let clock: any Clocking
    private let timings: () -> Timings
    /// The wait after which the announcement goes away, while it runs.
    private(set) var announcing: Task<Void, Never>?
    private var isClosed = false
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
         positions: PlaybackCoordinator,
         clock: any Clocking,
         timings: @escaping () -> Timings = { Timings() }) {
        self.playable = playable
        self.origin = origin
        self.mode = mode
        self.starter = starter
        self.positions = positions
        self.clock = clock
        self.timings = timings
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
            watch(playback.player)
            state = .playing(playback)
            playback.player.play()
            // After it plays, so that asking NPO which series an episode
            // from search belongs to does not hold the picture up.
            origin = await positions.origin(of: playable, given: origin, in: mode)
            await positions.started(playable, from: origin, in: mode)
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
        isClosed = true
        announcing?.cancel()
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
        writing = Task {
            await self.ended()
        }
    }

    /// What is playing reached its end. The next episode of its series
    /// starts, and the player says so for a while; with nothing to go on to,
    /// the sitting is over (FR-PLAY-05, FR-PLAY-07).
    ///
    /// Kids mode pauses first, for as long as the settings say now, and
    /// counts it down: a moment to stop before the next episode carries a
    /// child along. A pause of nothing is normal mode's way (FR-PLAY-06).
    func ended() async {
        let next = await positions.playedToEnd(playable.id, from: origin, in: mode)
        guard !isClosed else { return }
        guard let next else {
            isOver = true
            return
        }
        let pause = mode == .kids ? timings()[.kidsPause] : 0
        if pause > 0 {
            await countDown(pause, to: next.playable)
            guard !isClosed, !isOver else { return }
        }
        playable = next.playable
        origin = next.origin
        await start()
        // After a countdown that named it, it is not named again.
        guard pause == 0, case .playing = state, !isClosed else { return }
        announce(next.playable)
    }

    /// Shows the seconds left, one at a time. Stopping, or closing the
    /// player, ends it early.
    private func countDown(_ seconds: Int, to next: Playable) async {
        stopWatching()
        for remaining in stride(from: seconds, to: 0, by: -1) {
            state = .pausing(before: next, remaining: remaining)
            let waited = (try? await clock.wait(for: .seconds(1))) != nil
            guard waited, !isClosed, !isOver else { return }
        }
    }

    /// Somebody chose not to go on — with the episode that started by itself,
    /// or during the countdown before it: back to where playback was started
    /// from (FR-PLAY-05, FR-PLAY-06).
    func stopGoingOn() {
        isOver = true
    }

    private func announce(_ playable: Playable) {
        announcing?.cancel()
        announced = playable
        announcing = Task { [clock] in
            // Cancelled when the next announcement, or the end, comes first.
            guard (try? await clock.wait(for: Self.announcementTime)) != nil else { return }
            self.announced = nil
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
