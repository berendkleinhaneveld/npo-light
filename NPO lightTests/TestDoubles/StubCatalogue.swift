//
//  StubCatalogue.swift
//  NPO lightTests
//

import Foundation
import Synchronization
@testable import NPO_light

/// A `Catalogue` that answers a search from a closure and remembers what it
/// was asked, in the app's own types (ADR 0009).
nonisolated final class StubCatalogue: Catalogue {
    struct Search: Equatable {
        let query: String
        let mode: Mode
    }

    static let results = SearchResults(
        series: [SeriesSummary(id: ItemID(rawValue: "series-1"), title: "Freeks wilde wereld", artwork: nil)],
        singleProgrammes: [],
        episodes: []
    )

    static let seasons = [
        Season(id: SeasonID(rawValue: "season-1"), title: "Seizoen 1"),
        Season(id: SeasonID(rawValue: "season-2"), title: "Seizoen 2")
    ]

    static let detail = SeriesDetail(id: ItemID(rawValue: "series-1"),
                                     title: "Freeks wilde wereld",
                                     synopsis: "Freek Vonk reist de wereld over.",
                                     artwork: nil,
                                     seasons: StubCatalogue.seasons)

    private let answer: @Sendable (String) async throws -> SearchResults
    private let detail: @Sendable (ItemID) async throws -> SeriesDetail
    private let season: @Sendable (SeasonID) async throws -> [Playable]
    private let place: @Sendable (EpisodeID) async throws -> SeriesPlace?
    private let asked = Mutex<[Search]>([])
    private let askedSeasons = Mutex<[SeasonID]>([])

    init(
        answer: @escaping @Sendable (String) async throws -> SearchResults = { _ in StubCatalogue.results },
        detail: @escaping @Sendable (ItemID) async throws -> SeriesDetail = { _ in StubCatalogue.detail },
        season: @escaping @Sendable (SeasonID) async throws -> [Playable] = { StubCatalogue.episodes(of: $0) },
        place: @escaping @Sendable (EpisodeID) async throws -> SeriesPlace? = { _ in nil }
    ) {
        self.place = place
        self.answer = answer
        self.detail = detail
        self.season = season
    }

    /// Two episodes named after their season.
    static func episodes(of season: SeasonID) -> [Playable] {
        (1...2).map { number in
            Playable(id: EpisodeID(rawValue: "\(season.rawValue)-\(number)"),
                     title: "\(season.rawValue) aflevering \(number)",
                     caption: "Afl. \(number) • 10m",
                     synopsis: nil,
                     duration: nil,
                     artwork: nil)
        }
    }

    /// Every season whose episodes were asked for, oldest first.
    var seasonRequests: [SeasonID] { askedSeasons.withLock { $0 } }

    /// Every search that reached the catalogue, oldest first.
    var searches: [Search] { asked.withLock { $0 } }

    func availableModes() async throws -> Set<Mode> {
        [.normal]
    }

    func search(for query: String, in mode: Mode) async throws -> SearchResults {
        asked.withLock { $0.append(Search(query: query, mode: mode)) }
        return try await answer(query)
    }

    func series(_ id: ItemID, in mode: Mode) async throws -> SeriesDetail {
        try await detail(id)
    }

    func episodes(of season: SeasonID, in mode: Mode) async throws -> [Playable] {
        askedSeasons.withLock { $0.append(season) }
        return try await self.season(season)
    }

    func place(of episode: EpisodeID, in mode: Mode) async throws -> SeriesPlace? {
        try await place(episode)
    }
}
