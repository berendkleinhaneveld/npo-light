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
nonisolated final class NPOCatalogue: Catalogue {
    private struct KnownProfiles {
        /// The sign-in these profiles belong to. Another account has others.
        let marker: String
        let byMode: [Mode: String]
    }

    private let authenticator: NPOAuthenticator
    private let known = Mutex<KnownProfiles?>(nil)

    init(authenticator: NPOAuthenticator) {
        self.authenticator = authenticator
    }

    // MARK: Catalogue

    /// Always asks NPO: a kids profile made on a phone a minute ago should be
    /// found without signing in again.
    func availableModes() async throws -> Set<Mode> {
        Set(try await fetchProfiles().keys)
    }

    func search(for query: String, in mode: Mode) async throws -> SearchResults {
        let call = BackendCall(path: NPOWire.searchPath,
                               query: [URLQueryItem(name: "query", value: query),
                                       URLQueryItem(name: "page", value: "1")],
                               profile: try await profile(for: mode))
        return try await body(SearchBody.self, from: call).results
    }

    func series(_ id: ItemID, in mode: Mode) async throws -> SeriesDetail {
        let call = BackendCall(path: NPOWire.seriesPath(id), profile: try await profile(for: mode))
        return try await body(SeriesPageBody.self, from: call).detail
    }

    func episodes(of season: SeasonID, in mode: Mode) async throws -> [Playable] {
        // `asc` is broadcast order, and what NPO's own app asks for.
        let call = BackendCall(path: NPOWire.episodesPath(season),
                               query: [URLQueryItem(name: "sort", value: "asc")],
                               profile: try await profile(for: mode))
        return try await body([CatalogueItemBody].self, from: call).compactMap(\.playable)
    }

    // MARK: profiles

    private func profile(for mode: Mode) async throws -> String {
        let marker = try authenticator.signInMarker()
        let remembered = known.withLock { $0?.marker == marker ? $0?.byMode : nil }
        let profiles: [Mode: String]
        if let remembered {
            profiles = remembered
        } else {
            profiles = try await fetchProfiles()
        }
        guard let profile = profiles[mode] else {
            // Normal mode without a general profile is not a state NPO has
            // ever shown; kids mode without a kids profile is an ordinary one.
            throw mode == .kids ? BackendError.kidsProfileMissing : BackendError.unexpectedResponse(status: nil)
        }
        return profile
    }

    /// The first general profile and the first kids profile, in NPO's order.
    private func fetchProfiles() async throws -> [Mode: String] {
        let marker = try authenticator.signInMarker()
        let profiles = try await body([ProfileBody].self, from: BackendCall(path: NPOWire.profilesPath))
        var byMode: [Mode: String] = [:]
        byMode[.normal] = profiles.first { $0.type == ProfileBody.generalType }?.guid
        byMode[.kids] = profiles.first { $0.type == ProfileBody.kidsType }?.guid
        known.withLock { $0 = KnownProfiles(marker: marker, byMode: byMode) }
        return byMode
    }

    // MARK: the wire

    private func body<Body: Decodable>(_ type: Body.Type, from call: BackendCall) async throws -> Body {
        let response = try await authenticator.backendResponse(to: call)
        switch response.status {
        case 200:
            do {
                return try JSONDecoder().decode(type, from: response.body)
            } catch {
                throw BackendError.unexpectedResponse(status: response.status)
            }
        case 404:
            throw BackendError.itemUnavailable
        default:
            throw BackendError.unexpectedResponse(status: response.status)
        }
    }
}
