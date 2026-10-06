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
    private let later: any WatchLater
    private let order: EpisodeOrder
    private let clock: any Clocking

    init(watched: WatchedState, order: EpisodeOrder, clock: any Clocking) {
        progress = watched.progress
        history = watched.history
        later = watched.later
        self.order = order
        self.clock = clock
    }

    /// `playable` started playing. Its item — the series it is an episode
    /// of, or itself — now continues with it, whatever it continued with
    /// before, and is the most recently watched (FR-PLAY-09). Something whose
    /// series is not known records nothing.
    func started(_ playable: Playable, from origin: PlayOrigin, in mode: Mode) async {
        let entry: WatchedEntry
        switch origin {
        case .series(let place):
            entry = WatchedEntry(series: place.series,
                                 next: Upcoming(playable, in: place.season),
                                 playedAt: clock.now)
        case .single:
            entry = WatchedEntry(single: playable, playedAt: clock.now)
        case .unknown:
            return
        }
        // An entry that could not be written costs the thread, and must not
        // stop what is playing.
        try? await history.record(entry, in: mode)
    }

    /// NPO says where `id` was left, as playing it was asked for: taken over
    /// when it is news, before the resume point is read (FR-PLAY-13).
    func noticed(_ position: SharedPosition?, of id: EpisodeID, in mode: Mode) async {
        guard let position else { return }
        await SharedPositions(progress: progress, clock: clock).take([id: position], in: mode)
    }

    /// `id` was watched to its end on another device: everything that
    /// finishing it here would have set off (FR-HOME-12).
    func finishedElsewhere(_ id: EpisodeID, from origin: PlayOrigin, in mode: Mode) async {
        await finished(id, origin, in: mode)
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
    /// episode, when `origin` says where in the series it is.
    func played(_ id: EpisodeID,
                from origin: PlayOrigin = .unknown,
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
                                      updatedAt: clock.now,
                                      duration: Self.known(duration) ?? known?.duration,
                                      shared: known?.shared)
        await write(update, in: mode, resting: resting || finishing)
        if passedThreshold {
            await finished(id, origin, in: mode)
        }
    }

    /// Playback of `id` reached its end. That finishes it whatever its
    /// duration, which is the only way an item of unknown duration is
    /// finished.
    ///
    /// Answers what plays after it: the episode its series now continues
    /// with. Nothing after a single programme, after a series' last episode,
    /// or when what follows is not known (FR-PLAY-07).
    @discardableResult
    func playedToEnd(_ id: EpisodeID, from origin: PlayOrigin = .unknown, in mode: Mode) async -> PlayRequest? {
        let known = await progress.progress(of: id, in: mode)
        let update = PlaybackProgress(id: id,
                                      offset: nil,
                                      finishedAt: known?.finishedAt ?? clock.now,
                                      updatedAt: clock.now,
                                      duration: known?.duration,
                                      shared: known?.shared)
        await write(update, in: mode, resting: true)
        await finished(id, origin, in: mode)
        guard case .series(let place) = origin,
              let entry = await history.entry(for: place.series.id, in: mode),
              let next = entry.next, next.id != id else { return nil }
        return PlayRequest(playable: next.playable, origin: entry.origin)
    }

    /// Where an episode sits in its series, for one started from a list that
    /// did not say: NPO is asked, once it plays. Anything else is answered
    /// as it was given, and so is an episode NPO could not place.
    func origin(of playable: Playable, given origin: PlayOrigin, in mode: Mode) async -> PlayOrigin {
        guard origin == .unknown else { return origin }
        guard let place = try? await order.catalogue.place(of: playable.id, in: mode) else { return .unknown }
        return .series(place)
    }

    /// Everything that finishing `id` sets off, from the one place that sees
    /// the threshold passed (ADR 0006): its series moves on, and it leaves
    /// the watch later list (FR-LATER-07).
    private func finished(_ id: EpisodeID, _ origin: PlayOrigin, in mode: Mode) async {
        await moveOn(from: id, origin, in: mode)
        try? await later.remove(id, in: mode)
    }

    /// A duration worth keeping: the player answers with something that is
    /// not a number while it does not know.
    private static func known(_ duration: TimeInterval?) -> TimeInterval? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        return duration
    }

    /// The item continues with what follows `id`: the next episode of its
    /// series, or nothing — a single programme, or a series' last episode —
    /// which finishes it (FR-HOME-07). Only while it still continues with
    /// `id`: this is asked at every write past the threshold, and answers
    /// once.
    ///
    /// When NPO cannot say what follows, the series stays on `id` until
    /// another episode is played.
    private func moveOn(from id: EpisodeID, _ origin: PlayOrigin, in mode: Mode) async {
        let item: ItemID
        switch origin {
        case .series(let place): item = place.series.id
        case .single: item = ItemID(rawValue: id.rawValue)
        case .unknown: return
        }
        guard var entry = await history.entry(for: item, in: mode), entry.next?.id == id else { return }
        if case .series(let place) = origin {
            do {
                entry.next = try await order.following(id, at: place, in: mode)
            } catch {
                return
            }
        } else {
            entry.next = nil
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
