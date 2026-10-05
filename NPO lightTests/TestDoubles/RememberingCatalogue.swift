//
//  RememberingCatalogue.swift
//  NPO lightTests
//

import Foundation
@testable import NPO_light

/// A catalogue that remembers what it is told to, over a `StubCatalogue`
/// that answers afresh: the two halves of a cached catalogue, each under a
/// test's control.
nonisolated struct RememberingCatalogue: Catalogue {
    var series: SeriesDetail?
    var episodes: [SeasonID: [Playable]] = [:]
    var programme: ProgrammeDetail?
    let fresh: StubCatalogue

    func availableModes() async throws -> Set<Mode> { try await fresh.availableModes() }

    func search(for query: String, in mode: Mode) async throws -> SearchResults {
        try await fresh.search(for: query, in: mode)
    }

    func series(_ id: ItemID, in mode: Mode) async throws -> SeriesDetail {
        try await fresh.series(id, in: mode)
    }

    func programme(_ id: EpisodeID, in mode: Mode) async throws -> ProgrammeDetail {
        try await fresh.programme(id, in: mode)
    }

    func episodes(of season: SeasonID, in mode: Mode) async throws -> [Playable] {
        try await fresh.episodes(of: season, in: mode)
    }

    func place(of episode: EpisodeID, in mode: Mode) async throws -> SeriesPlace? {
        try await fresh.place(of: episode, in: mode)
    }

    func rememberedSeries(_ id: ItemID, in mode: Mode) async -> SeriesDetail? { series }

    func rememberedEpisodes(of season: SeasonID, in mode: Mode) async -> [Playable]? { episodes[season] }

    func rememberedProgramme(_ id: EpisodeID, in mode: Mode) async -> ProgrammeDetail? { programme }
}
