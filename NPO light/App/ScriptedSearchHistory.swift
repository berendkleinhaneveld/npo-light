//
//  ScriptedSearchHistory.swift
//  NPO light
//

#if DEBUG
import Foundation

/// A `SearchHistory` that is gone when the process is, for previews and for
/// the app when a test launches it (ADR 0009). Debug builds only.
actor ScriptedSearchHistory: SearchHistory {
    private var lists: [Mode: SearchHistoryList]

    init(_ lists: [Mode: SearchHistoryList] = [:]) {
        self.lists = lists
    }

    /// Two terms, one with something picked for it.
    static var filled: ScriptedSearchHistory {
        var list = SearchHistoryList()
        list.remember("klokhuis", picking: nil)
        list.remember("fr", picking: PickedItem(.series(ScriptedCatalogue.results.series[0])))
        return ScriptedSearchHistory([.normal: list])
    }

    func searches(in mode: Mode) -> [RecentSearch] {
        lists[mode]?.searches ?? []
    }

    func remember(_ term: String, picking pick: PickedItem?, in mode: Mode) {
        lists[mode, default: SearchHistoryList()].remember(term, picking: pick)
    }

    func forget(_ term: String, in mode: Mode) {
        lists[mode]?.forget(term)
    }

    func clear(in mode: Mode) {
        lists[mode] = nil
    }
}

extension SearchModel {
    /// A search screen over the scripted catalogue, for previews.
    static func scripted(history: ScriptedSearchHistory = ScriptedSearchHistory(),
                         mode: Mode = .normal) -> SearchModel {
        SearchModel(catalogue: ScriptedCatalogue(), history: history, clock: SystemClock(), mode: mode)
    }
}
#endif
