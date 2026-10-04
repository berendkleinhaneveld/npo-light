//
//  WatchLaterStoreTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// The watch later list as it is kept: each test has a suite of defaults of
/// its own, and removes it again.
struct WatchLaterStoreTests {
    private static let series = SeriesSummary(id: ItemID(rawValue: "series"), title: "Serie", artwork: nil)
    private static let season = SeasonID(rawValue: "season-1")

    private static func playable(_ name: String) -> Playable {
        Playable(id: EpisodeID(rawValue: name), title: name, caption: "Afl. 1 • 10m", synopsis: "Not kept.",
                 duration: nil, artwork: URL(string: "https://assets.example/\(name).jpg"))
    }

    private static func film(_ name: String) -> SavedItem {
        SavedItem(playable(name), origin: .single)
    }

    private func withSuite(_ body: (String) async throws -> Void) async throws {
        let suite = "later-tests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        try await body(suite)
    }

    @Test("FR-LATER-04: saving puts an item at the front, and saving it again moves it there")
    func mostRecentlySavedFirst() async throws {
        try await withSuite { suite in
            let store = WatchLaterStore(suite: suite)
            try await store.save(Self.film("first"), in: .normal)
            try await store.save(Self.film("second"), in: .normal)
            #expect(await store.saved(in: .normal).map(\.episode.title) == ["second", "first"])

            try await store.remove(EpisodeID(rawValue: "first"), in: .normal)
            try await store.save(Self.film("first"), in: .normal)

            #expect(await store.saved(in: .normal).map(\.episode.title) == ["first", "second"])
        }
    }

    @Test("FR-LATER-02: saving what is already saved does not make a second entry")
    func savingTwiceIsOneEntry() async throws {
        try await withSuite { suite in
            let store = WatchLaterStore(suite: suite)

            try await store.save(Self.film("same"), in: .normal)
            try await store.save(Self.film("same"), in: .normal)

            #expect(await store.saved(in: .normal).count == 1)
        }
    }

    @Test("FR-LATER-02: two episodes of one series are two entries, each knowing its series and season")
    func episodesAreSavedOnTheirOwn() async throws {
        try await withSuite { suite in
            let store = WatchLaterStore(suite: suite)
            let place = PlayOrigin.series(SeriesPlace(series: Self.series, season: Self.season))

            try await store.save(SavedItem(Self.playable("one"), origin: place), in: .normal)
            try await store.save(SavedItem(Self.playable("two"), origin: place), in: .normal)

            let saved = await store.saved(in: .normal)
            #expect(saved.map(\.id.rawValue) == ["two", "one"])
            #expect(saved.allSatisfy { $0.origin == place && $0.series == Self.series })
        }
    }

    @Test("FR-LATER-01, NFR-REL-04: the list and its order are still there after a relaunch, with what a tile needs")
    func listSurvivesARelaunch() async throws {
        try await withSuite { suite in
            let store = WatchLaterStore(suite: suite)
            try await store.save(Self.film("first"), in: .normal)
            try await store.save(SavedItem(Self.playable("episode"), origin: .unknown), in: .normal)

            let saved = await WatchLaterStore(suite: suite).saved(in: .normal)

            #expect(saved.map(\.id.rawValue) == ["episode", "first"])
            #expect(saved.map(\.origin) == [.unknown, .single])
            #expect(saved.first?.episode.artwork == URL(string: "https://assets.example/episode.jpg"))
        }
    }

    @Test("FR-LATER-06: the list is not capped")
    func listIsNotCapped() async throws {
        try await withSuite { suite in
            let store = WatchLaterStore(suite: suite)

            for number in 1...(ContinueWatching.cap + 5) {
                try await store.save(Self.film("film-\(number)"), in: .normal)
            }

            #expect(await store.saved(in: .normal).count == ContinueWatching.cap + 5)
        }
    }

    @Test("FR-LATER-09: removing takes that item off, stays off, and leaves pins and what was watched alone")
    func removingLeavesTheRest() async throws {
        try await withSuite { suite in
            let store = WatchLaterStore(suite: suite)
            try await store.save(Self.film("first"), in: .normal)
            try await store.save(Self.film("second"), in: .normal)
            try await PinStore(suite: suite).pin(Self.series, in: .normal)
            let entry = WatchedEntry(single: Self.playable("first"), playedAt: Date(timeIntervalSince1970: 0))
            try await WatchHistoryStore(suite: suite).record(entry, in: .normal)

            try await store.remove(EpisodeID(rawValue: "first"), in: .normal)

            #expect(await WatchLaterStore(suite: suite).saved(in: .normal).map(\.id.rawValue) == ["second"])
            #expect(await PinStore(suite: suite).pinned(in: .normal) == [Self.series])
            #expect(await WatchHistoryStore(suite: suite).entries(in: .normal) == [entry])
        }
    }

    @Test("FR-LATER-01: unpinning a series leaves its saved episode on the list")
    func unpinningLeavesSavedEpisodes() async throws {
        try await withSuite { suite in
            let pins = PinStore(suite: suite)
            try await pins.pin(Self.series, in: .normal)
            let store = WatchLaterStore(suite: suite)
            let place = PlayOrigin.series(SeriesPlace(series: Self.series, season: Self.season))
            try await store.save(SavedItem(Self.playable("one"), origin: place), in: .normal)

            try await pins.unpin(Self.series.id, in: .normal)

            #expect(await store.saved(in: .normal).count == 1)
        }
    }

    @Test("FR-LATER-10: what one mode saved is not on the other's list")
    func modesAreKeptApart() async throws {
        try await withSuite { suite in
            let store = WatchLaterStore(suite: suite)

            try await store.save(Self.film("film"), in: .kids)

            #expect(await store.saved(in: .normal).isEmpty)
            #expect(await store.saved(in: .kids).count == 1)
        }
    }

    @Test("NFR-REL-04: the list counts towards the one ceiling, and an item past it is refused")
    func listCountsTowardsTheCeiling() async throws {
        try await withSuite { suite in
            let pins = PinStore(suite: suite, ceiling: 300)
            let long = SeriesSummary(id: ItemID(rawValue: "a"), title: String(repeating: "x", count: 200), artwork: nil)
            try await pins.pin(long, in: .normal)
            let store = WatchLaterStore(suite: suite, ceiling: 300)

            await #expect(throws: LocalDataError.full) {
                try await store.save(Self.film("one too many"), in: .normal)
            }
        }
    }
}
