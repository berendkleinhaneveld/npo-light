//
//  EpisodeOrder.swift
//  NPO light
//

import Foundation

/// Which episode follows which (FR-CONTENT-02): the next one of its season,
/// and after a season's last the first of the season that follows.
nonisolated struct EpisodeOrder: Sendable {
    let catalogue: any Catalogue

    /// The episode after `id` that can be played, or `nil` when none follows:
    /// one NPO no longer has, or will not let this account play, is passed
    /// over (FR-CONTENT-02, FR-PLAY-07).
    ///
    /// Throws when NPO could not be asked, or no longer lists `id` in its
    /// season: then what follows it is not known, which is not the same as
    /// nothing following it.
    func following(_ id: EpisodeID, at place: SeriesPlace, in mode: Mode) async throws -> Upcoming? {
        let episodes = try await catalogue.episodes(of: place.season, in: mode)
        guard let index = episodes.firstIndex(where: { $0.id == id }) else {
            throw BackendError.itemUnavailable
        }
        for episode in episodes.dropFirst(index + 1) where await isPlayable(episode, in: mode) {
            return Upcoming(episode, in: place.season)
        }
        // The seasons are asked for at a season's end, and not carried along:
        // a new one may have been added since the episode was started.
        let seasons = try await catalogue.series(place.series.id, in: mode).broadcastOrder
        guard let current = seasons.firstIndex(of: place.season) else { return nil }
        // A season with nothing in it, or nothing that plays, is passed over.
        for season in seasons.dropFirst(current + 1) {
            let listed = try await catalogue.episodes(of: season, in: mode)
            for episode in listed where await isPlayable(episode, in: mode) {
                return Upcoming(episode, in: season)
            }
        }
        return nil
    }

    /// What the episode's own page says, since a season's list does not.
    /// Only a clear no passes an episode over: when NPO cannot be asked, the
    /// episode is tried, and the player says what is wrong if it is.
    private func isPlayable(_ episode: Playable, in mode: Mode) async -> Bool {
        do {
            return try await catalogue.programme(episode.id, in: mode).isPlayable
        } catch BackendError.itemUnavailable {
            return false
        } catch {
            return true
        }
    }
}
