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

        /// Playback is held while the player asks whether anyone is still
        /// watching, for this many seconds more (FR-PLAY-08).
        case asking(Playback, remaining: Int)
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

    /// It is over because nobody answered whether they were still watching:
    /// the app goes back to its home page (FR-PLAY-08).
    private(set) var wasLeftUnattended = false

    private let starter: any PlaybackStarting
    private let positions: PlaybackCoordinator

    /// What NPO is told of this sitting, or `nil` when it is told nothing.
    let reports: PlaybackReports?
    private let clock: any Clocking
    private let timings: () -> Timings
    /// The wait after which the announcement goes away, while it runs.
    private(set) var announcing: Task<Void, Never>?
    private var isClosed = false
    private let watcher = PlayerWatcher()
    private var attention: Attention

    /// The wait for an answer to the still-watching prompt, while it runs.
    private(set) var asking: Task<Void, Never>?

    /// The latest write of the position, while it is under way.
    private(set) var writing: Task<Void, Never>?

    init(playable: Playable,
         origin: PlayOrigin = .unknown,
         mode: Mode,
         starter: any PlaybackStarting,
         positions: PlaybackCoordinator,
         clock: any Clocking,
         reports: PlaybackReports? = nil,
         timings: @escaping () -> Timings = { Timings() }) {
        self.reports = reports
        self.playable = playable
        self.origin = origin
        self.mode = mode
        self.starter = starter
        self.positions = positions
        self.clock = clock
        self.timings = timings
        attention = Attention(at: clock.now)
    }

    /// What is loaded, while something plays or is held for the prompt.
    private var playback: Playback? {
        switch state {
        case .playing(let playback), .asking(let playback, _): playback
        case .preparing, .pausing, .failed: nil
        }
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
            // Before the resume point is read: where it was left on another
            // device is where it goes on (FR-PLAY-13).
            await positions.noticed(playback.position, of: playable.id, in: mode)
            await resume(playback.player)
            watch(playback.player)
            state = .playing(playback)
            // The app starting something is nobody touching the remote.
            attention.expectOwnChange(at: clock.now)
            playback.player.play()
            report { $0.began($1) }
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
        asking?.cancel()
        rest()
        report { $0.stopped($1) }
        stopWatching()
        playback?.player.pause()
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
        guard let playback, let item = playback.player.currentItem else { return }
        let position = playback.player.currentTime().seconds
        let duration = item.duration.seconds
        writing = Task { [positions, id = playable.id, origin, mode] in
            await positions.played(id, from: origin, to: position, of: duration, in: mode, resting: resting)
        }
    }

    private func stopWatching() {
        watcher.stop()
    }

    /// Where playback is now, as NPO is told (FR-PLAY-12). The length is the
    /// player's, and NPO's own for as long as the player does not know.
    private var moment: PlaybackReports.Moment? {
        guard let playback, let item = playback.player.currentItem else { return nil }
        let length = item.duration.seconds
        return PlaybackReports.Moment(episode: playable.id,
                                      position: playback.player.currentTime().seconds,
                                      duration: length.isFinite && length > 0 ? length : playback.duration,
                                      mode: mode)
    }

    private func report(_ what: (PlaybackReports, PlaybackReports.Moment) -> Void) {
        guard let reports, let moment else { return }
        what(reports, moment)
    }

    /// Somebody moved through what plays, from one position to another.
    func sought(from origin: TimeInterval, to target: TimeInterval) {
        report { reports, moment in
            reports.sought(from: origin,
                           to: PlaybackReports.Moment(episode: moment.episode,
                                                      position: target,
                                                      duration: moment.duration,
                                                      mode: moment.mode))
        }
    }

    /// A stream that stops being playable — a licence that could not be
    /// obtained, a manifest that would not load — becomes a problem with a
    /// retry rather than a black screen.
    ///
    /// While it plays its position is written at a fixed interval, at every
    /// pause, and when it reaches the end (FR-PLAY-03).
    private func watch(_ player: AVPlayer) {
        watcher.watch(player, telling: PlayerWatcher.Events(
            failed: { [weak self] in self?.playbackFailed() },
            paused: { [weak self] in
                self?.rest()
                self?.report { $0.paused($1) }
            },
            playing: { [weak self] in self?.report { $0.resumed($1) } },
            tick: { [weak self] in
                self?.record(resting: false)
                self?.report { $0.ticked($1) }
                self?.checkAttention()
            },
            ended: { [weak self] in self?.playedToEnd() },
            interacted: { [weak self] in self?.interacted() }
        ))
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
        report { $0.completed($1) }
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

    /// What was playing stopped being playable. The position survives the
    /// failure, so that a retry carries on from where the stream stopped
    /// (FR-PLAY-10).
    func playbackFailed() {
        rest()
        stopWatching()
        state = .failed(.failed)
    }

    // MARK: Still watching (FR-PLAY-08)

    /// How long this mode plays before it asks, in seconds.
    var attentionLimit: Int {
        timings()[mode == .kids ? .kidsStillWatching : .normalStillWatching]
    }

    /// Somebody paused, resumed or scrubbed: the count of unattended
    /// playback starts again.
    func interacted() {
        attention.noticed(at: clock.now)
    }

    /// Asks, when it has played for as long as the mode's setting says with
    /// nobody touching the remote. Looked at whenever the position is
    /// written, which is often enough for a limit counted in hours.
    func checkAttention() {
        guard case .playing(let playback) = state,
              attention.isDue(at: clock.now, after: .seconds(attentionLimit)) else { return }
        ask(holding: playback)
    }

    /// Somebody is still watching: on from exactly where the prompt held it,
    /// and the count starts again.
    func keepWatching() {
        guard case .asking(let playback, _) = state else { return }
        asking?.cancel()
        attention.confirmed(at: clock.now)
        attention.expectOwnChange(at: clock.now)
        state = .playing(playback)
        playback.player.play()
    }

    /// Holds playback and waits for an answer. With none in time the sitting
    /// is over, and the app goes home.
    private func ask(holding playback: Playback) {
        attention.expectOwnChange(at: clock.now)
        playback.player.pause()
        state = .asking(playback, remaining: Attention.grace)
        asking?.cancel()
        asking = Task { [clock] in
            for remaining in stride(from: Attention.grace, to: 0, by: -1) {
                guard case .asking(let held, _) = self.state else { return }
                self.state = .asking(held, remaining: remaining)
                guard (try? await clock.wait(for: .seconds(1))) != nil else { return }
            }
            guard case .asking = self.state, !self.isClosed else { return }
            self.wasLeftUnattended = true
            self.isOver = true
        }
    }
}
