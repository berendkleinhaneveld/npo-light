//
//  PlaybackCoordinator.swift
//  NPO light
//

import Foundation

/// Where the rules of playback that span more than one screen live
/// (ADR 0011): what counts as finished (FR-PLAY-04), where to resume
/// (FR-PLAY-02), what is written down while something plays (FR-PLAY-03),
/// and which episode a series continues with (FR-PLAY-09).
///
/// It knows positions as numbers and nothing about a player, so that every
/// rule here is tested without one.
@MainActor
final class PlaybackCoordinator {
    /// How often the position is written while something plays: what a hard
    /// stop can cost (FR-PLAY-03).
    static let interval: TimeInterval = 10

    private let progress: any ProgressKeeping
    private let history: any WatchHistory
    private let order: EpisodeOrder
    private let clock: any Clocking

    init(progress: any ProgressKeeping, history: any WatchHistory, order: EpisodeOrder, clock: any Clocking) {
        self.progress = progress
        self.history = history
        self.order = order
        self.clock = clock
    }

    /// `playable` started playing. When its place in a series is known, that
    /// series now continues with it, whichever episode it continued with
    /// before, and is the most recently watched (FR-PLAY-09).
    func started(_ playable: Playable, at place: SeriesPlace?, in mode: Mode) async {
        guard let place else { return }
        let entry = WatchedEntry(series: place.series,
                                 next: Upcoming(playable, in: place.season),
                                 playedAt: clock.now)
        // An entry that could not be written costs the thread, and must not
        // stop what is playing.
        try? await history.record(entry, in: mode)
    }

    /// Where playing `id` starts: its stored position, or `nil` for the
    /// beginning — nothing stored, or it was finished and is now played
    /// again deliberately.
    func resumePoint(of id: EpisodeID, in mode: Mode) async -> TimeInterval? {
        guard let offset = await progress.progress(of: id, in: mode)?.offset, offset > 0 else { return nil }
        return offset
    }

    /// Playback of `id` is at `position`. `resting` says that it stopped
    /// there — paused, closed, sent to the background — rather than that the
    /// interval came round.
    ///
    /// Past the completion threshold the item is finished and has no position
    /// left to resume: stopping in the credits must not resume in the
    /// credits.
    ///
    /// Passing the threshold is also what moves its series on to the next
    /// episode, when `place` says where in the series it is.
    func played(_ id: EpisodeID,
                at place: SeriesPlace? = nil,
                to position: TimeInterval,
                of duration: TimeInterval?,
                in mode: Mode,
                resting: Bool) async {
        // Nothing was played yet: a stream that never started must not wipe
        // the position it was going to resume from (FR-PLAY-10).
        guard position.isFinite, position > 0 else { return }
        let known = await progress.progress(of: id, in: mode)
        let passedThreshold = Completion.isFinished(at: position, of: duration)
        let finishing = passedThreshold && known?.finishedAt == nil
        let update = PlaybackProgress(id: id,
                                      offset: passedThreshold ? nil : position,
                                      finishedAt: finishing ? clock.now : known?.finishedAt,
                                      updatedAt: clock.now)
        await write(update, in: mode, resting: resting || finishing)
        if passedThreshold {
            await moveOn(from: id, at: place, in: mode)
        }
    }

    /// Playback of `id` reached its end. That finishes it whatever its
    /// duration, which is the only way an item of unknown duration is
    /// finished.
    func playedToEnd(_ id: EpisodeID, at place: SeriesPlace? = nil, in mode: Mode) async {
        let known = await progress.progress(of: id, in: mode)
        let update = PlaybackProgress(id: id,
                                      offset: nil,
                                      finishedAt: known?.finishedAt ?? clock.now,
                                      updatedAt: clock.now)
        await write(update, in: mode, resting: true)
        await moveOn(from: id, at: place, in: mode)
    }

    /// The series continues with the episode after `id`, or is finished when
    /// there is none (FR-HOME-07). Only while it still continues with `id`:
    /// this is asked at every write past the threshold, and answers once.
    ///
    /// When NPO cannot say what follows, the series stays on `id` until
    /// another episode is played.
    private func moveOn(from id: EpisodeID, at place: SeriesPlace?, in mode: Mode) async {
        guard let place,
              var entry = await history.entry(for: place.series.id, in: mode),
              entry.next?.id == id else { return }
        do {
            entry.next = try await order.following(id, at: place, in: mode)
        } catch {
            return
        }
        entry.finishedAt = entry.next == nil ? clock.now : nil
        try? await history.record(entry, in: mode)
    }

    private func write(_ update: PlaybackProgress, in mode: Mode, resting: Bool) async {
        // A position that could not be written costs a resume point, and
        // must not stop what is playing.
        if resting {
            try? await progress.keep(update, in: mode)
        } else {
            try? await progress.note(update, in: mode)
        }
    }
}
