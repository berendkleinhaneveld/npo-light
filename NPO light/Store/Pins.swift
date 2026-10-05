//
//  Pins.swift
//  NPO light
//

import Foundation

/// One mode's pinned series, and the rules for the list (FR-HOME-02,
/// FR-HOME-03).
///
/// A pin is the series as a tile needs it — its own title and image — so that
/// the tile can be drawn, and removed, when NPO no longer has the series
/// (ADR 0012, FR-CONTENT-05).
nonisolated struct PinList: Sendable, Equatable, Codable {
    /// Most recently pinned first.
    private(set) var series: [SeriesSummary] = []

    /// The episode each series starts with, by the series' identifier, where
    /// its page knew one when it was pinned: what lets a tile name and play
    /// an episode of a series nobody started, without asking NPO
    /// (FR-HOME-04). Absent in a list kept before this was.
    private(set) var starts: [String: Upcoming]?

    func contains(_ id: ItemID) -> Bool {
        series.contains { $0.id == id }
    }

    /// The episode `id` starts with, when one was kept.
    func start(of id: ItemID) -> Upcoming? {
        starts?[id.rawValue]
    }

    /// Puts `pinned` at the front. A series that is already pinned keeps its
    /// one tile and moves there.
    mutating func pin(_ pinned: SeriesSummary, startingWith start: Upcoming? = nil) {
        unpin(pinned.id)
        series.insert(pinned, at: 0)
        if let start {
            starts = (starts ?? [:]).merging([pinned.id.rawValue: start]) { _, new in new }
        }
    }

    mutating func unpin(_ id: ItemID) {
        series.removeAll { $0.id == id }
        starts?[id.rawValue] = nil
    }
}

nonisolated extension PinList {
    /// ``starts``, by the app's own identifier.
    var startsByItem: [ItemID: Upcoming] {
        Dictionary(uniqueKeysWithValues: (starts ?? [:]).map { (ItemID(rawValue: $0.key), $0.value) })
    }
}

/// The series each mode has pinned (ADR 0011, ADR 0012). Only a series is
/// pinned, which is why this takes nothing else (FR-HOME-03).
nonisolated protocol Pins: Sendable {
    /// Most recently pinned first.
    func pinned(in mode: Mode) async -> [SeriesSummary]

    func isPinned(_ id: ItemID, in mode: Mode) async -> Bool

    /// The episode each pinned series starts with, for those that were
    /// pinned with one.
    func starts(in mode: Mode) async -> [ItemID: Upcoming]

    /// Pins `series`. `start` is the episode its page would play for
    /// somebody who has not started it, when the page knows one.
    func pin(_ series: SeriesSummary, startingWith start: Upcoming?, in mode: Mode) async throws

    /// Takes the pin away and nothing else: not what was watched of the
    /// series, nor where (FR-HOME-05).
    func unpin(_ id: ItemID, in mode: Mode) async throws
}

/// The pins as they are kept on the television: in `UserDefaults`, where tvOS
/// does not reach (ADR 0015).
actor PinStore: Pins {
    private let defaults: LocalDefaults

    init(suite: String? = nil, ceiling: Int = LocalDefaults.ceiling) {
        defaults = LocalDefaults(suite: suite, ceiling: ceiling)
    }

    func pinned(in mode: Mode) -> [SeriesSummary] {
        list(in: mode).series
    }

    func isPinned(_ id: ItemID, in mode: Mode) -> Bool {
        list(in: mode).contains(id)
    }

    func starts(in mode: Mode) -> [ItemID: Upcoming] {
        list(in: mode).startsByItem
    }

    func pin(_ series: SeriesSummary, startingWith start: Upcoming?, in mode: Mode) throws {
        var list = list(in: mode)
        list.pin(series, startingWith: start)
        try defaults.keep(list, for: .pins, in: mode)
    }

    /// Pins a series whose first episode is not known.
    func pin(_ series: SeriesSummary, in mode: Mode) throws {
        try pin(series, startingWith: nil, in: mode)
    }

    func unpin(_ id: ItemID, in mode: Mode) throws {
        var list = list(in: mode)
        list.unpin(id)
        try defaults.keep(list, for: .pins, in: mode)
    }

    private func list(in mode: Mode) -> PinList {
        defaults.value(PinList.self, for: .pins, in: mode) ?? PinList()
    }
}
