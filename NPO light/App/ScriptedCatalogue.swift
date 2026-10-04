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
        singleProgrammes: [
            Playable(id: EpisodeID(rawValue: "playable-2"),
                     title: "De wilde stad",
                     caption: "1u 25m",
                     synopsis: nil,
                     duration: .seconds(5100),
                     artwork: nil)
        ],
        episodes: [
            Playable(id: EpisodeID(rawValue: "playable-1"),
                     title: "Freeks wilde wereld",
                     caption: "10m • Afl. 5: Haaien in de rivier",
                     synopsis: nil,
                     duration: .seconds(628),
                     artwork: nil)
        ]
    )

    static let seasons = [
        Season(id: SeasonID(rawValue: "season-1"), title: "Seizoen 1"),
        Season(id: SeasonID(rawValue: "season-2"), title: "Seizoen 2"),
        Season(id: SeasonID(rawValue: "season-3"), title: "Kort")
    ]

    func availableModes() async throws -> Set<Mode> {
        [.normal]
    }

    func search(for query: String, in mode: Mode) async throws -> SearchResults {
        Self.results
    }

    func series(_ id: ItemID, in mode: Mode) async throws -> SeriesDetail {
        SeriesDetail(id: id,
                     title: "Freeks wilde wereld",
                     synopsis: "Freek Vonk reist de wereld over, op zoek naar de meest bijzondere dieren.",
                     artwork: nil,
                     seasons: Self.seasons)
    }

    /// Episodes that carry their season in their name, so that a test can
    /// tell which season is on screen — and more of them than fit on it, as a
    /// real season has: a list that scrolls is where focus went astray.
    func episodes(of season: SeasonID, in mode: Mode) async throws -> [Playable] {
        (1...12).map { number in
            Playable(id: EpisodeID(rawValue: "\(season.rawValue)-episode-\(number)"),
                     title: "\(season.rawValue) aflevering \(number)",
                     caption: "Afl. \(number) • 10m",
                     synopsis: "Beschrijving van aflevering \(number).",
                     duration: nil,
                     artwork: nil)
        }
    }
}
#endif
