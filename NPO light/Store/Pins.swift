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

    func contains(_ id: ItemID) -> Bool {
        series.contains { $0.id == id }
    }

    /// Puts `pinned` at the front. A series that is already pinned keeps its
    /// one tile and moves there.
    mutating func pin(_ pinned: SeriesSummary) {
        unpin(pinned.id)
        series.insert(pinned, at: 0)
    }

    mutating func unpin(_ id: ItemID) {
        series.removeAll { $0.id == id }
    }
}

/// The series each mode has pinned (ADR 0011, ADR 0012). Only a series is
/// pinned, which is why this takes nothing else (FR-HOME-03).
nonisolated protocol Pins: Sendable {
    /// Most recently pinned first.
    func pinned(in mode: Mode) async -> [SeriesSummary]

    func isPinned(_ id: ItemID, in mode: Mode) async -> Bool

    func pin(_ series: SeriesSummary, in mode: Mode) async throws

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

    func pin(_ series: SeriesSummary, in mode: Mode) throws {
        var list = list(in: mode)
        list.pin(series)
        try defaults.keep(list, for: .pins, in: mode)
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
