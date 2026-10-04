//
//  SearchHistory.swift
//  NPO light
//

import Foundation

/// The recent searches of each mode (ADR 0011, ADR 0012).
///
/// Every method takes the mode: one mode's searches are never the other's
/// (FR-MODE-05).
nonisolated protocol SearchHistory: Sendable {
    /// Most recent first.
    func searches(in mode: Mode) async -> [RecentSearch]

    /// Remembers `term` as the most recent search and, when something was
    /// picked from its results, that it was picked for this term.
    func remember(_ term: String, picking pick: PickedItem?, in mode: Mode) async throws

    /// Forgets one term and what was picked for it.
    func forget(_ term: String, in mode: Mode) async throws

    /// Forgets every term of this mode. The other mode keeps its own.
    func clear(in mode: Mode) async
}

/// The search history as it is kept on the television: in `UserDefaults`,
/// where tvOS does not reach (ADR 0015).
actor SearchHistoryStore: SearchHistory {
    private let defaults: LocalDefaults

    init(suite: String? = nil, ceiling: Int = LocalDefaults.ceiling) {
        defaults = LocalDefaults(suite: suite, ceiling: ceiling)
    }

    func searches(in mode: Mode) -> [RecentSearch] {
        list(in: mode).searches
    }

    func remember(_ term: String, picking pick: PickedItem?, in mode: Mode) throws {
        var list = list(in: mode)
        list.remember(term, picking: pick)
        try keep(list, in: mode)
    }

    func forget(_ term: String, in mode: Mode) throws {
        var list = list(in: mode)
        list.forget(term)
        try keep(list, in: mode)
    }

    func clear(in mode: Mode) {
        defaults.remove(.searchHistory, in: mode)
    }

    /// What cannot be read is treated as no history: the next search writes a
    /// readable one over it.
    private func list(in mode: Mode) -> SearchHistoryList {
        guard let data = defaults.data(for: .searchHistory, in: mode),
              let list = try? JSONDecoder().decode(SearchHistoryList.self, from: data) else {
            return SearchHistoryList()
        }
        return list
    }

    private func keep(_ list: SearchHistoryList, in mode: Mode) throws {
        try defaults.write(try JSONEncoder().encode(list), for: .searchHistory, in: mode)
    }
}
