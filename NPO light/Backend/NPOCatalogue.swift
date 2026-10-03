//
//  NPOCatalogue.swift
//  NPO light
//

import Foundation
import Synchronization

/// The catalogue of NPO's app backend (ADR 0008).
///
/// A mode is browsed as one of the account's own NPO profiles, and that is the
/// whole of the youth filter: NPO applies its own definition of the youth
/// catalogue to whatever the profile asks for (ADR 0014). Nothing here filters
/// on an age rating, which would be the wrong rule — NPO gates on the series,
/// not on the episode.
///
/// Its entrances are `@concurrent`, so that a search typed on the main actor is
/// fetched and decoded off it (FR-SEARCH-03, NFR-PERF-05).
nonisolated final class NPOCatalogue: Catalogue {
    private let authenticator: NPOAuthenticator
    private let profiles: NPOProfiles

    init(authenticator: NPOAuthenticator, profiles: NPOProfiles) {
        self.authenticator = authenticator
        self.profiles = profiles
    }

    convenience init(authenticator: NPOAuthenticator) {
        self.init(authenticator: authenticator, profiles: NPOProfiles(authenticator: authenticator))
    }

    // MARK: Catalogue

    /// Always asks NPO: a kids profile made on a phone a minute ago should be
    /// found without signing in again.
    @concurrent
    func availableModes() async throws -> Set<Mode> {
        try await profiles.refreshedModes()
    }

    @concurrent
    func search(for query: String, in mode: Mode) async throws -> SearchResults {
        let call = BackendCall(path: NPOWire.searchPath,
                               query: [URLQueryItem(name: "query", value: query),
                                       URLQueryItem(name: "page", value: "1")],
                               profile: try await profiles.profile(for: mode))
        return try await body(SearchBody.self, from: call).results
    }

    @concurrent
    func series(_ id: ItemID, in mode: Mode) async throws -> SeriesDetail {
        let call = BackendCall(path: NPOWire.seriesPath(id), profile: try await profiles.profile(for: mode))
        return try await body(SeriesPageBody.self, from: call).detail
    }

    @concurrent
    func episodes(of season: SeasonID, in mode: Mode) async throws -> [Playable] {
        // `asc` is broadcast order, and what NPO's own app asks for.
        let call = BackendCall(path: NPOWire.episodesPath(season),
                               query: [URLQueryItem(name: "sort", value: "asc")],
                               profile: try await profiles.profile(for: mode))
        return try await body([CatalogueItemBody].self, from: call).compactMap(\.playable)
    }

    // MARK: the wire

    private func body<Body: Decodable>(_ type: Body.Type, from call: BackendCall) async throws -> Body {
        try await authenticator.backendBody(type, from: call)
    }
}
