//
//  NewEpisodes.swift
//  NPO light
//

import Foundation

/// Finds out that a series which was watched to its end has more to watch
/// (FR-HOME-14, ADR 0031).
///
/// What a series continues with is written down when an episode is played.
/// A series that continues with nothing would say so for good: this asks NPO
/// whether that is still true, and writes down what it finds.
nonisolated struct NewEpisodes: Sendable {
    /// How many seasons, from the latest back, are searched for the last
    /// episode that was watched. A series is finished in its latest season,
    /// and what was added since is that season grown or one more.
    static let seasonsSearched = 2

    private let order: EpisodeOrder
    private let watched: WatchedState

    init(catalogue: any Catalogue, watched: WatchedState) {
        order = EpisodeOrder(catalogue: catalogue)
        self.watched = watched
    }

    /// Asks NPO about those of `series` that continue with nothing.
    ///
    /// - Returns: whether one of them now continues with an episode. NPO not
    ///   answering changes nothing.
    func take(for series: [ItemID], in mode: Mode) async -> Bool {
        var changed = false
        for id in series {
            guard var entry = await watched.history.entry(for: id, in: mode),
                  entry.kind == .series, entry.next == nil,
                  let next = try? await added(to: entry, in: mode) else { continue }
            entry.next = next
            entry.finishedAt = nil
            // When it was played stays what it was: finding an episode is
            // not watching one, and the tile keeps its place.
            if (try? await watched.history.record(entry, in: mode)) != nil {
                changed = true
            }
        }
        return changed
    }

    private func added(to entry: WatchedEntry, in mode: Mode) async throws -> Upcoming? {
        let catalogue = order.catalogue
        let detail = try await catalogue.series(entry.id, in: mode)
        // A programme followed as it is broadcast offers its latest episode,
        // as its own page does (FR-HOME-04).
        if detail.listsNewestFirst {
            guard let season = detail.seasons.first?.id,
                  let latest = try await catalogue.episodes(of: season, in: mode).last,
                  await watched.progress.progress(of: latest.id, in: mode)?.isFinished != true else { return nil }
            return Upcoming(latest, in: season)
        }
        // Any other series goes on after the last episode that was watched.
        for season in detail.broadcastOrder.suffix(Self.seasonsSearched).reversed() {
            let listed = try await catalogue.episodes(of: season, in: mode)
            let positions = await watched.progress.progress(of: listed.map(\.id), in: mode)
            guard let last = listed.last(where: { positions[$0.id]?.isFinished == true }) else { continue }
            return try await order.following(last.id, at: SeriesPlace(series: entry.series, season: season), in: mode)
        }
        return nil
    }
}
