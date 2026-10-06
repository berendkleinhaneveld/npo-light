//
//  ContinuedElsewhere.swift
//  NPO light
//

import Foundation

/// Puts what NPO lists for a profile to go on with on the television's own
/// row: something started on a phone is then on the home page (FR-HOME-12,
/// ADR 0028).
///
/// The row stays the television's. NPO's list says what is new on it, once:
/// what it repeats later does not bring back something the row moved on
/// from, or that was taken off it by hand.
@MainActor
final class ContinuedElsewhere {
    /// How soon NPO is asked again after it answered. The home page comes
    /// back on screen far more often than something is watched elsewhere,
    /// and the answer is NPO's whole home page.
    static let pace: TimeInterval = 60

    private var answeredAt: [Mode: Date] = [:]
    private let catalogue: any Catalogue
    private let history: any WatchHistory
    private let positions: SharedPositions
    private let coordinator: PlaybackCoordinator
    private let clock: any Clocking

    init(catalogue: any Catalogue, watched: WatchedState, coordinator: PlaybackCoordinator, clock: any Clocking) {
        self.catalogue = catalogue
        history = watched.history
        positions = SharedPositions(progress: watched.progress, clock: clock)
        self.coordinator = coordinator
        self.clock = clock
    }

    /// Asks NPO and takes in what is news.
    ///
    /// - Returns: whether anything a home page shows changed. NPO not
    ///   answering changes nothing.
    func take(in mode: Mode) async -> Bool {
        if let answeredAt = answeredAt[mode], clock.now.timeIntervalSince(answeredAt) < Self.pace { return false }
        guard let listed = try? await catalogue.continuing(in: mode) else { return false }
        answeredAt[mode] = clock.now
        var changed = false
        // The last one first, so that NPO's first ends at the front, and a
        // second apart: NPO gives an order and no times.
        for (index, item) in listed.enumerated().reversed() {
            let playedAt = clock.now.addingTimeInterval(-TimeInterval(index))
            if await take(item, playedAt: playedAt, in: mode) {
                changed = true
            }
        }
        return changed
    }

    /// Something was taken off the television's row by hand: NPO is asked to
    /// take what it continues with off its own, as NPO's app would
    /// (FR-HOME-13). NPO not answering leaves its row as it is.
    func remove(_ episode: EpisodeID, in mode: Mode) async {
        try? await catalogue.discontinue(episode, in: mode)
    }

    /// A mode was erased: everything NPO lists for its profile is taken off
    /// NPO's row, or the next look at it would fill the television's again
    /// (FR-SET-05).
    ///
    /// NPO acts on that a few seconds after it answers, so its row is left
    /// unread for ``pace``: what it still lists meanwhile is what was just
    /// erased.
    func clear(in mode: Mode) async {
        let listed = (try? await catalogue.continuing(in: mode)) ?? []
        for item in listed {
            try? await catalogue.discontinue(item.playable.id, in: mode)
        }
        answeredAt[mode] = clock.now
    }

    private func take(_ item: Continued, playedAt: Date, in mode: Mode) async -> Bool {
        let id = item.playable.id
        guard let position = item.playable.position,
              await !positions.isKnown(position, of: id, in: mode) else { return false }
        let isFinished = Completion.isFinished(at: position.offset, of: position.duration)

        // What the row already continues with keeps its place, and stays off
        // the row when it was taken off (FR-HOME-08).
        if let entry = await history.entries(in: mode).first(where: { $0.next?.id == id }) {
            await positions.take([id: position], in: mode)
            if isFinished {
                await coordinator.finishedElsewhere(id, from: entry.origin, in: mode)
            }
            return true
        }
        // Watched to its end elsewhere: nothing to go on with.
        guard !isFinished else {
            await positions.take([id: position], in: mode)
            return false
        }
        // Asked before the position is taken: an episode NPO could not place
        // now is still news the next time.
        guard let entry = await entry(for: item, playedAt: playedAt, in: mode) else { return false }
        await positions.take([id: position], in: mode)
        return (try? await history.record(entry, in: mode)) != nil
    }

    /// The row's entry for what NPO lists: its series continuing with it, or
    /// the programme itself when it belongs to none. `nil` when NPO could
    /// not be asked which.
    private func entry(for item: Continued, playedAt: Date, in mode: Mode) async -> WatchedEntry? {
        guard !item.isSingle else { return WatchedEntry(single: item.playable, playedAt: playedAt) }
        do {
            guard let place = try await catalogue.place(of: item.playable.id, in: mode) else {
                return WatchedEntry(single: item.playable, playedAt: playedAt)
            }
            return WatchedEntry(series: place.series,
                                next: Upcoming(item.playable, in: place.season),
                                playedAt: playedAt)
        } catch {
            return nil
        }
    }
}

/// Erasing a mode on the television and on NPO's row for its profile, so that
/// what was erased stays away (FR-SET-05).
nonisolated struct ErasingElsewhere: LocalDataErasing {
    private let wrapped: any LocalDataErasing
    private let elsewhere: ContinuedElsewhere

    init(wrapping wrapped: any LocalDataErasing, elsewhere: ContinuedElsewhere) {
        self.wrapped = wrapped
        self.elsewhere = elsewhere
    }

    func erase(_ modes: Set<Mode>) async {
        // The television first: it is erased whether or not NPO answers.
        await wrapped.erase(modes)
        for mode in modes {
            await elsewhere.clear(in: mode)
        }
    }
}
