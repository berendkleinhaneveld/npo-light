//
//  WatchHistory.swift
//  NPO light
//

import Foundation

/// What each mode started watching, and where each of those continues
/// (ADR 0011, ADR 0012).
nonisolated protocol WatchHistory: Sendable {
    /// Most recently played first.
    func entries(in mode: Mode) async -> [WatchedEntry]

    func entry(for id: ItemID, in mode: Mode) async -> WatchedEntry?

    /// Keeps `entry` in place of what was kept for its series, at the front.
    func record(_ entry: WatchedEntry, in mode: Mode) async throws
}

/// What was watched, as a page reads it: how far each episode was played,
/// and where each series continues.
nonisolated struct WatchedState: Sendable {
    let progress: any ProgressKeeping
    let history: any WatchHistory
}

/// The entries as they are kept on the television: in `UserDefaults`, where
/// tvOS does not reach (ADR 0015).
actor WatchHistoryStore: WatchHistory {
    private let defaults: LocalDefaults

    init(suite: String? = nil, ceiling: Int = LocalDefaults.ceiling) {
        defaults = LocalDefaults(suite: suite, ceiling: ceiling)
    }

    func entries(in mode: Mode) -> [WatchedEntry] {
        list(in: mode).entries
    }

    func entry(for id: ItemID, in mode: Mode) -> WatchedEntry? {
        list(in: mode).entry(for: id)
    }

    func record(_ entry: WatchedEntry, in mode: Mode) throws {
        var list = list(in: mode)
        list.record(entry)
        try defaults.keep(list, for: .watched, in: mode)
    }

    private func list(in mode: Mode) -> WatchedList {
        defaults.value(WatchedList.self, for: .watched, in: mode) ?? WatchedList()
    }
}
