//
//  ScriptedCatalogue.swift
//  NPO light
//

#if DEBUG
import Foundation

/// A `Catalogue` that never leaves the process, for previews and for the app
/// when a test launches it (ADR 0009). Debug builds only.
nonisolated struct ScriptedCatalogue: Catalogue {
    static let results = SearchResults(
        series: [
            SeriesSummary(id: ItemID(rawValue: "series-1"), title: "Freeks wilde wereld", artwork: nil),
            SeriesSummary(id: ItemID(rawValue: "series-2"), title: "Het Klokhuis", artwork: nil)
        ],
        playables: [
            Playable(id: EpisodeID(rawValue: "playable-1"),
                     title: "Freeks wilde wereld",
                     caption: "10m • Afl. 5: Haaien in de rivier",
                     synopsis: nil,
                     duration: .seconds(628),
                     artwork: nil)
        ]
    )

    func availableModes() async throws -> Set<Mode> {
        [.normal]
    }

    func search(for query: String, in mode: Mode) async throws -> SearchResults {
        Self.results
    }

    func series(_ id: ItemID, in mode: Mode) async throws -> SeriesDetail {
        SeriesDetail(id: id, title: "Freeks wilde wereld", synopsis: nil, artwork: nil, seasons: [])
    }

    func episodes(of season: SeasonID, in mode: Mode) async throws -> [Playable] {
        Self.results.playables
    }
}
#endif
