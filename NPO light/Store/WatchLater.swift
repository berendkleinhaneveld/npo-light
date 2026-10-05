//
//  WatchLater.swift
//  NPO light
//

import Foundation

/// One thing saved to watch later: a single programme or one episode, never
/// a series (FR-LATER-02, ADR 0005).
///
/// It carries what its tile needs, so that it can be drawn — and taken off
/// the list — when NPO no longer has it (FR-LATER-11).
nonisolated struct SavedItem: Sendable, Equatable, Codable, Identifiable {
    /// What will play.
    let episode: Upcoming

    /// The series it is an episode of, when whoever saved it knew.
    let series: SeriesSummary?

    /// It belongs to no series (FR-CONTENT-01).
    let isSingle: Bool

    var id: EpisodeID { episode.id }

    init(_ playable: Playable, origin: PlayOrigin) {
        switch origin {
        case .series(let place):
            episode = Upcoming(playable, in: place.season)
            series = place.series
            isSingle = false
        case .single, .unknown:
            episode = Upcoming(playable, in: nil)
            series = nil
            isSingle = origin == .single
        }
    }

    /// What playing it needs to be told.
    var origin: PlayOrigin {
        if let series, let season = episode.season {
            return .series(SeriesPlace(series: series, season: season))
        }
        return isSingle ? .single : .unknown
    }
}

/// One mode's watch later list, and its rules: most recently saved first,
/// one entry for one thing, and no cap (FR-LATER-04, FR-LATER-06).
nonisolated struct WatchLaterList: Sendable, Equatable, Codable {
    private(set) var items: [SavedItem] = []

    func contains(_ id: EpisodeID) -> Bool {
        items.contains { $0.id == id }
    }

    /// Puts `item` at the front. Saved again, it moves there.
    mutating func save(_ item: SavedItem) {
        remove(item.id)
        items.insert(item, at: 0)
    }

    mutating func remove(_ id: EpisodeID) {
        items.removeAll { $0.id == id }
    }
}

/// What each mode saved to watch later (ADR 0005, ADR 0011).
nonisolated protocol WatchLater: Sendable {
    /// Most recently saved first.
    func saved(in mode: Mode) async -> [SavedItem]

    func save(_ item: SavedItem, in mode: Mode) async throws

    /// Takes the item off the list and nothing else: not where it was
    /// watched to, nor a pin (FR-LATER-09).
    func remove(_ id: EpisodeID, in mode: Mode) async throws
}

/// The list as it is kept on the television: in `UserDefaults`, where tvOS
/// does not reach (ADR 0015).
actor WatchLaterStore: WatchLater {
    private let defaults: LocalDefaults

    init(suite: String? = nil, ceiling: Int = LocalDefaults.ceiling) {
        defaults = LocalDefaults(suite: suite, ceiling: ceiling)
    }

    func saved(in mode: Mode) -> [SavedItem] {
        list(in: mode).items
    }

    func save(_ item: SavedItem, in mode: Mode) throws {
        var list = list(in: mode)
        list.save(item)
        try defaults.keep(list, for: .later, in: mode)
    }

    func remove(_ id: EpisodeID, in mode: Mode) throws {
        var list = list(in: mode)
        guard list.contains(id) else { return }
        list.remove(id)
        try defaults.keep(list, for: .later, in: mode)
    }

    private func list(in mode: Mode) -> WatchLaterList {
        defaults.value(WatchLaterList.self, for: .later, in: mode) ?? WatchLaterList()
    }
}
