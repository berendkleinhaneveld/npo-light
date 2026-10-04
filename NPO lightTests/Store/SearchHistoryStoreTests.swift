//
//  SearchHistoryStoreTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// The search history as it is kept: each test has a suite of defaults of its
/// own, and removes it again.
struct SearchHistoryStoreTests {
    private static func item(_ name: String) -> PickedItem {
        PickedItem(.series(SeriesSummary(id: ItemID(rawValue: name), title: name, artwork: nil)))
    }

    /// Runs `body` against a suite nothing else uses.
    private func withSuite(_ body: (String) async throws -> Void) async throws {
        let suite = "search-history-tests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        try await body(suite)
    }

    @Test("FR-SEARCH-04: the most recent term is first, and a term searched again moves to the front")
    func mostRecentFirst() async throws {
        try await withSuite { suite in
            let store = SearchHistoryStore(suite: suite)

            try await store.remember("klokhuis", picking: nil, in: .normal)
            try await store.remember("fr", picking: nil, in: .normal)
            try await store.remember("klokhuis", picking: nil, in: .normal)

            #expect(await store.searches(in: .normal).map(\.term) == ["klokhuis", "fr"])
        }
    }

    @Test("FR-SEARCH-04: the list is capped, and the oldest term is the one dropped")
    func oldestTermIsDropped() async throws {
        try await withSuite { suite in
            let store = SearchHistoryStore(suite: suite)

            for number in 1...(SearchHistoryList.termCap + 1) {
                try await store.remember("term \(number)", picking: nil, in: .normal)
            }

            let terms = await store.searches(in: .normal).map(\.term)
            #expect(terms.count == SearchHistoryList.termCap)
            #expect(terms.first == "term \(SearchHistoryList.termCap + 1)")
            #expect(!terms.contains("term 1"))
        }
    }

    @Test("FR-SEARCH-04, NFR-REL-04: the history is still there after a relaunch")
    func historySurvivesARelaunch() async throws {
        try await withSuite { suite in
            try await SearchHistoryStore(suite: suite).remember("fr", picking: Self.item("freek"), in: .normal)

            let relaunched = SearchHistoryStore(suite: suite)

            #expect(await relaunched.searches(in: .normal) == [RecentSearch(term: "fr", picks: [Self.item("freek")])])
        }
    }

    @Test("FR-SEARCH-05: another pick for the same term is added to it, without duplicating the term")
    func picksGatherUnderOneTerm() async throws {
        try await withSuite { suite in
            let store = SearchHistoryStore(suite: suite)

            try await store.remember("fr", picking: Self.item("freeks wilde wereld"), in: .normal)
            try await store.remember("fr", picking: Self.item("freek in het wild"), in: .normal)

            #expect(await store.searches(in: .normal) == [
                RecentSearch(term: "fr", picks: [Self.item("freek in het wild"), Self.item("freeks wilde wereld")])
            ])
        }
    }

    @Test("FR-SEARCH-05: picking the same item twice does not duplicate it; it moves to the front")
    func samePickMovesToTheFront() async throws {
        try await withSuite { suite in
            let store = SearchHistoryStore(suite: suite)

            try await store.remember("fr", picking: Self.item("one"), in: .normal)
            try await store.remember("fr", picking: Self.item("two"), in: .normal)
            try await store.remember("fr", picking: Self.item("one"), in: .normal)

            #expect(await store.searches(in: .normal).first?.picks == [Self.item("one"), Self.item("two")])
        }
    }

    @Test("FR-SEARCH-05: searching a term again without a pick keeps what was picked for it")
    func searchingAgainKeepsThePicks() async throws {
        try await withSuite { suite in
            let store = SearchHistoryStore(suite: suite)

            try await store.remember("fr", picking: Self.item("one"), in: .normal)
            try await store.remember("fr", picking: nil, in: .normal)

            #expect(await store.searches(in: .normal) == [RecentSearch(term: "fr", picks: [Self.item("one")])])
        }
    }

    @Test("FR-SEARCH-05: a term keeps its most recent picks, up to a fixed number")
    func picksAreCapped() async throws {
        try await withSuite { suite in
            let store = SearchHistoryStore(suite: suite)

            for number in 1...(SearchHistoryList.pickCap + 1) {
                try await store.remember("fr", picking: Self.item("item \(number)"), in: .normal)
            }

            let picks = try #require(await store.searches(in: .normal).first?.picks)
            #expect(picks.count == SearchHistoryList.pickCap)
            #expect(picks.first == Self.item("item \(SearchHistoryList.pickCap + 1)"))
            #expect(!picks.contains(Self.item("item 1")))
        }
    }

    @Test("FR-SEARCH-07: deleting a term removes it and its picks, and stays removed")
    func deletedTermStaysDeleted() async throws {
        try await withSuite { suite in
            let store = SearchHistoryStore(suite: suite)
            try await store.remember("klokhuis", picking: nil, in: .normal)
            try await store.remember("fr", picking: Self.item("freek"), in: .normal)

            try await store.forget("fr", in: .normal)

            #expect(await store.searches(in: .normal) == [RecentSearch(term: "klokhuis", picks: [])])
            #expect(await SearchHistoryStore(suite: suite).searches(in: .normal).map(\.term) == ["klokhuis"])
        }
    }

    @Test("FR-SEARCH-07, FR-MODE-05: each mode has a history of its own, and clearing one leaves the other")
    func modesAreKeptApart() async throws {
        try await withSuite { suite in
            let store = SearchHistoryStore(suite: suite)
            try await store.remember("fr", picking: nil, in: .normal)
            try await store.remember("bram", picking: nil, in: .kids)
            #expect(await store.searches(in: .normal).map(\.term) == ["fr"])
            #expect(await store.searches(in: .kids).map(\.term) == ["bram"])

            await store.clear(in: .normal)

            #expect(await store.searches(in: .normal).isEmpty)
            #expect(await store.searches(in: .kids).map(\.term) == ["bram"])
        }
    }

    @Test("NFR-REL-04: a write that would take the defaults past their ceiling is refused, and nothing is lost")
    func writePastTheCeilingIsRefused() async throws {
        try await withSuite { suite in
            let store = SearchHistoryStore(suite: suite, ceiling: 200)
            try await store.remember("fr", picking: nil, in: .normal)

            await #expect(throws: LocalDataError.full) {
                try await store.remember(String(repeating: "x", count: 300), picking: nil, in: .normal)
            }

            #expect(await store.searches(in: .normal).map(\.term) == ["fr"])
        }
    }

    @Test("NFR-REL-04: the ceiling counts both modes together")
    func ceilingCountsBothModes() async throws {
        try await withSuite { suite in
            let store = SearchHistoryStore(suite: suite, ceiling: 200)
            try await store.remember(String(repeating: "x", count: 100), picking: nil, in: .normal)

            await #expect(throws: LocalDataError.full) {
                try await store.remember(String(repeating: "y", count: 100), picking: nil, in: .kids)
            }

            var defaults = LocalDefaults(suite: suite, ceiling: 200)
            #expect(defaults.size <= 200)
            defaults = LocalDefaults(suite: suite)
            #expect(defaults.ceiling < 512 * 1024)
        }
    }

    @Test("NFR-REL-05: a history that cannot be read is an empty one, and the next search replaces it")
    func unreadableHistoryIsEmpty() async throws {
        try await withSuite { suite in
            try LocalDefaults(suite: suite).write(Data("not a history".utf8), for: .searchHistory, in: .normal)
            let store = SearchHistoryStore(suite: suite)
            #expect(await store.searches(in: .normal).isEmpty)

            try await store.remember("fr", picking: nil, in: .normal)

            #expect(await store.searches(in: .normal).map(\.term) == ["fr"])
        }
    }
}
