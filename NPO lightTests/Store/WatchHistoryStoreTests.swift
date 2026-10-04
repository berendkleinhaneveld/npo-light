//
//  WatchHistoryStoreTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// What was watched, as it is kept: each test has a suite of defaults of its
/// own, and removes it again.
struct WatchHistoryStoreTests {
    private static let season = SeasonID(rawValue: "season-1")

    private static func entry(_ name: String, episode: String = "one", played: TimeInterval = 0) -> WatchedEntry {
        let playable = Playable(id: EpisodeID(rawValue: "\(name)-\(episode)"),
                                title: episode,
                                caption: "Afl. 1 • 10m",
                                synopsis: "Not kept.",
                                duration: nil,
                                artwork: URL(string: "https://assets.example/\(episode).jpg"))
        return WatchedEntry(series: SeriesSummary(id: ItemID(rawValue: name), title: name, artwork: nil),
                            next: Upcoming(playable, in: season),
                            playedAt: Date(timeIntervalSince1970: played))
    }

    private func withSuite(_ body: (String) async throws -> Void) async throws {
        let suite = "watched-tests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        try await body(suite)
    }

    @Test("FR-PLAY-09: what was played last is first")
    func mostRecentlyPlayedFirst() async throws {
        try await withSuite { suite in
            let store = WatchHistoryStore(suite: suite)

            try await store.record(Self.entry("first"), in: .normal)
            try await store.record(Self.entry("second"), in: .normal)

            #expect(await store.entries(in: .normal).map(\.series.title) == ["second", "first"])
        }
    }

    @Test("FR-PLAY-09: a series is recorded once, and updated for each episode")
    func seriesIsRecordedOnce() async throws {
        try await withSuite { suite in
            let store = WatchHistoryStore(suite: suite)
            try await store.record(Self.entry("series", episode: "one"), in: .normal)
            try await store.record(Self.entry("other"), in: .normal)

            try await store.record(Self.entry("series", episode: "two", played: 10), in: .normal)

            let entries = await store.entries(in: .normal)
            #expect(entries.map(\.series.title) == ["series", "other"])
            #expect(entries.first?.next?.title == "two")
            #expect(await store.entry(for: ItemID(rawValue: "series"), in: .normal) == entries.first)
        }
    }

    @Test("NFR-REL-04: what was watched is still there after a relaunch, with what its tile needs")
    func entriesSurviveARelaunch() async throws {
        try await withSuite { suite in
            let entry = Self.entry("series")
            try await WatchHistoryStore(suite: suite).record(entry, in: .normal)

            let read = await WatchHistoryStore(suite: suite).entry(for: entry.id, in: .normal)

            #expect(read == entry)
            #expect(read?.next?.playable.artwork == URL(string: "https://assets.example/one.jpg"))
        }
    }

    @Test("FR-MODE-05: what one mode watched is not the other's")
    func modesAreKeptApart() async throws {
        try await withSuite { suite in
            let store = WatchHistoryStore(suite: suite)

            try await store.record(Self.entry("journaal"), in: .normal)

            #expect(await store.entries(in: .kids).isEmpty)
            #expect(await store.entry(for: ItemID(rawValue: "journaal"), in: .kids) == nil)
        }
    }

    @Test("NFR-REL-04: what was watched counts towards the one ceiling, and an entry past it is refused")
    func entriesCountTowardsTheCeiling() async throws {
        try await withSuite { suite in
            let pins = PinStore(suite: suite, ceiling: 300)
            try await pins.pin(SeriesSummary(id: ItemID(rawValue: "a"),
                                             title: String(repeating: "x", count: 200),
                                             artwork: nil),
                               in: .normal)
            let store = WatchHistoryStore(suite: suite, ceiling: 300)

            await #expect(throws: LocalDataError.full) {
                try await store.record(Self.entry("one too many"), in: .normal)
            }

            #expect(await store.entries(in: .normal).isEmpty)
        }
    }
}
