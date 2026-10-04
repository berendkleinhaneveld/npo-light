//
//  PlaybackCoordinator.swift
//  NPO light
//

import Foundation

/// Where the rules of playback that span more than one screen live
/// (ADR 0011): what counts as finished (FR-PLAY-04), where to resume
/// (FR-PLAY-02), and what is written down while something plays
/// (FR-PLAY-03).
///
/// It knows positions as numbers and nothing about a player, so that every
/// rule here is tested without one.
@MainActor
final class PlaybackCoordinator {
    /// How often the position is written while something plays: what a hard
    /// stop can cost (FR-PLAY-03).
    static let interval: TimeInterval = 10

    private let progress: any ProgressKeeping
    private let clock: any Clocking

    init(progress: any ProgressKeeping, clock: any Clocking) {
        self.progress = progress
        self.clock = clock
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
    func played(_ id: EpisodeID,
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
    }

    /// Playback of `id` reached its end. That finishes it whatever its
    /// duration, which is the only way an item of unknown duration is
    /// finished.
    func playedToEnd(_ id: EpisodeID, in mode: Mode) async {
        let known = await progress.progress(of: id, in: mode)
        let update = PlaybackProgress(id: id,
                                      offset: nil,
                                      finishedAt: known?.finishedAt ?? clock.now,
                                      updatedAt: clock.now)
        await write(update, in: mode, resting: true)
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
