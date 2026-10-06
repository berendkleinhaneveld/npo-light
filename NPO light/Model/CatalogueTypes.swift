//
//  CatalogueTypes.swift
//  NPO light
//

import Foundation

/// A series as a list shows it: enough to recognise it and to open it.
nonisolated struct SeriesSummary: Sendable, Hashable, Identifiable, Codable {
    let id: ItemID
    let title: String
    /// May be missing; a tile then draws a placeholder (FR-CONTENT-01).
    let artwork: URL?
}

/// Something that can be played: a single programme, or an episode of a
/// series.
///
/// The type does not say which. A list that knows keeps the two apart
/// (``SearchResults``), and nothing in a list names the series an episode
/// belongs to: only the answer to playing it does (Q-10).
nonisolated struct Playable: Sendable, Hashable, Identifiable, Codable {
    let id: EpisodeID
    let title: String

    /// NPO's own line under the title, such as `Afl. 1 • 10m`. The episode
    /// number exists nowhere else in a season's list, so it is shown as it
    /// comes rather than taken apart.
    let caption: String?

    let synopsis: String?

    /// Absent in a season's list, where it is only part of ``caption``.
    let duration: Duration?

    let artwork: URL?

    /// Where NPO says it was left, when the list it came in said so
    /// (FR-PLAY-13).
    var position: SharedPosition?
}

/// A programme that belongs to no series, as its own page describes it
/// (FR-CONTENT-03).
nonisolated struct ProgrammeDetail: Sendable, Equatable, Codable {
    /// The programme, with the fuller description its page has.
    let playable: Playable

    /// Whether NPO says it can be played now, by this account
    /// (FR-CONTENT-06).
    let isPlayable: Bool
}

/// What a search answers with, by kind (FR-SEARCH-10).
nonisolated struct SearchResults: Sendable, Equatable {
    let series: [SeriesSummary]

    /// What belongs to no series: a film, a one-off documentary, a special
    /// (FR-CONTENT-01).
    let singleProgrammes: [Playable]

    /// Episodes of series. A search for a series' name answers with a great
    /// many of these.
    let episodes: [Playable]

    static let empty = SearchResults(series: [], singleProgrammes: [], episodes: [])

    var isEmpty: Bool { series.isEmpty && singleProgrammes.isEmpty && episodes.isEmpty }
}

/// One season, named as NPO names it. The title is editorial — a series can
/// have a season called "Kort" — so it is never computed from a number.
nonisolated struct Season: Sendable, Equatable, Identifiable, Codable {
    let id: SeasonID
    let title: String
}

/// A series and its seasons (FR-CONTENT-02).
nonisolated struct SeriesDetail: Sendable, Equatable, Identifiable, Codable {
    let id: ItemID
    let title: String
    let synopsis: String?
    let artwork: URL?

    /// As NPO lists them, which is how the picker shows them: the first
    /// season first for most series, the latest first for a programme that
    /// has a season for each year.
    let seasons: [Season]

    /// ``seasons`` runs from the latest back to the first.
    var listsNewestFirst = false

    /// The seasons from the first to the latest: the order in which one
    /// follows another.
    var broadcastOrder: [SeasonID] {
        let listed = seasons.map(\.id)
        return listsNewestFirst ? listed.reversed() : listed
    }
}
