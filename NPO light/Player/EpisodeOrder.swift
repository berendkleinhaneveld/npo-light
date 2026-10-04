//
//  EpisodeOrder.swift
//  NPO light
//

import Foundation

/// Which episode follows which (FR-CONTENT-02): the next one of its season,
/// and after a season's last the first of the season that follows.
nonisolated struct EpisodeOrder: Sendable {
    let catalogue: any Catalogue

    /// The episode after `id`, or `nil` when it is the last of its series.
    ///
    /// Throws when NPO could not be asked, or no longer lists `id` in its
    /// season: then what follows it is not known, which is not the same as
    /// nothing following it.
    func following(_ id: EpisodeID, at place: SeriesPlace, in mode: Mode) async throws -> Upcoming? {
        let episodes = try await catalogue.episodes(of: place.season, in: mode)
        guard let index = episodes.firstIndex(where: { $0.id == id }) else {
            throw BackendError.itemUnavailable
        }
        if index + 1 < episodes.count {
            return Upcoming(episodes[index + 1], in: place.season)
        }
        // The seasons are asked for at a season's end, and not carried along:
        // a new one may have been added since the episode was started.
        let seasons = try await catalogue.series(place.series.id, in: mode).broadcastOrder
        guard let current = seasons.firstIndex(of: place.season) else { return nil }
        // A season with nothing in it is passed over.
        for season in seasons.dropFirst(current + 1) {
            if let first = try await catalogue.episodes(of: season, in: mode).first {
                return Upcoming(first, in: season)
            }
        }
        return nil
    }
}
