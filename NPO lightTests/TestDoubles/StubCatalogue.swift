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
        playables: []
    )

    private let answer: @Sendable (String) async throws -> SearchResults
    private let asked = Mutex<[Search]>([])

    init(answer: @escaping @Sendable (String) async throws -> SearchResults = { _ in StubCatalogue.results }) {
        self.answer = answer
    }

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
        throw BackendError.itemUnavailable
    }

    func episodes(of season: SeasonID, in mode: Mode) async throws -> [Playable] {
        []
    }
}
