//
//  SearchHistoryTypes.swift
//  NPO light
//

import Foundation

/// What was chosen from a set of results.
nonisolated enum SearchPick: Sendable, Equatable {
    case series(SeriesSummary)

    /// A programme that belongs to no series (FR-CONTENT-01).
    case single(Playable)

    /// An episode of a series the list did not name (Q-10).
    case playable(Playable)
}

nonisolated extension SearchPick {
    var isSingle: Bool {
        if case .single = self { return true }
        return false
    }
}

/// Something picked from a search, as it is kept: enough to draw its tile and
/// to open it again without searching (FR-SEARCH-05, FR-SEARCH-06).
///
/// It carries its own title and image, so the tile can be drawn — and removed
/// — when NPO no longer has the item (ADR 0012).
nonisolated struct PickedItem: Sendable, Hashable, Codable, Identifiable {
    enum Kind: String, Sendable, Codable {
        case series
        /// A programme that belongs to no series.
        case single
        /// An episode, or something picked before the two were told apart. A list does not name the series
        /// an episode belongs to (Q-10), so the episode is what is kept.
        case playable
    }

    let kind: Kind
    let identifier: String
    let title: String
    let caption: String?
    let artwork: URL?

    var id: String { "\(kind.rawValue):\(identifier)" }

    init(_ pick: SearchPick) {
        switch pick {
        case .series(let series):
            kind = .series
            identifier = series.id.rawValue
            title = series.title
            caption = nil
            artwork = series.artwork
        case .single(let playable), .playable(let playable):
            kind = pick.isSingle ? .single : .playable
            identifier = playable.id.rawValue
            title = playable.title
            caption = playable.caption
            artwork = playable.artwork
        }
    }

    /// What opening it needs. The description and the duration were not kept:
    /// the player and the series page ask NPO for their own.
    var pick: SearchPick {
        switch kind {
        case .series:
            .series(SeriesSummary(id: ItemID(rawValue: identifier), title: title, artwork: artwork))
        case .single:
            .single(playable)
        case .playable:
            .playable(playable)
        }
    }

    private var playable: Playable {
        Playable(id: EpisodeID(rawValue: identifier),
                 title: title,
                 caption: caption,
                 synopsis: nil,
                 duration: nil,
                 artwork: artwork)
    }
}

/// A term that was searched for, with what was picked for it, most recently
/// picked first.
nonisolated struct RecentSearch: Sendable, Equatable, Codable, Identifiable {
    let term: String
    var picks: [PickedItem]

    var id: String { term }
}

/// One mode's search history, and the rules for what it keeps
/// (FR-SEARCH-04, FR-SEARCH-05, FR-SEARCH-07).
nonisolated struct SearchHistoryList: Sendable, Equatable, Codable {
    /// How many terms are kept. The oldest is dropped.
    static let termCap = 10

    /// How many picks a term keeps: what fits beside it on its row.
    static let pickCap = 4

    /// Most recent first.
    private(set) var searches: [RecentSearch] = []

    /// Moves `term` to the front, adding it if it is new, and puts `pick` at
    /// the front of what was picked for it.
    mutating func remember(_ term: String, picking pick: PickedItem?) {
        var picks = searches.first { $0.term == term }?.picks ?? []
        if let pick {
            picks.removeAll { $0.id == pick.id }
            picks.insert(pick, at: 0)
        }
        searches.removeAll { $0.term == term }
        searches.insert(RecentSearch(term: term, picks: Array(picks.prefix(Self.pickCap))), at: 0)
        searches = Array(searches.prefix(Self.termCap))
    }

    /// Removes `term` and what was picked for it.
    mutating func forget(_ term: String) {
        searches.removeAll { $0.term == term }
    }
}
