//
//  CatalogueTypes.swift
//  NPO light
//

import Foundation

/// A series as a list shows it: enough to recognise it and to open it.
nonisolated struct SeriesSummary: Sendable, Equatable, Identifiable {
    let id: ItemID
    let title: String
    /// May be missing; a tile then draws a placeholder (FR-CONTENT-01).
    let artwork: URL?
}

/// Something that can be played: a film, a standalone episode or an episode of
/// a series.
///
/// Which of the three it is, and which series it belongs to, is not in what
/// NPO returns for a list (Q-10), so this type does not claim to know.
nonisolated struct Playable: Sendable, Equatable, Identifiable {
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
}

/// What a search answers with. NPO keeps series and playable items apart, and
/// so does this.
nonisolated struct SearchResults: Sendable, Equatable {
    let series: [SeriesSummary]
    let playables: [Playable]

    static let empty = SearchResults(series: [], playables: [])

    var isEmpty: Bool { series.isEmpty && playables.isEmpty }
}

/// One season, named as NPO names it. The title is editorial — a series can
/// have a season called "Kort" — so it is never computed from a number.
nonisolated struct Season: Sendable, Equatable, Identifiable {
    let id: SeasonID
    let title: String
}

/// A series and its seasons, in broadcast order (FR-CONTENT-02).
nonisolated struct SeriesDetail: Sendable, Equatable, Identifiable {
    let id: ItemID
    let title: String
    let synopsis: String?
    let artwork: URL?
    let seasons: [Season]
}
