//
//  PinStoreTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// The pins as they are kept: each test has a suite of defaults of its own,
/// and removes it again.
struct PinStoreTests {
    private static func series(_ name: String) -> SeriesSummary {
        SeriesSummary(id: ItemID(rawValue: name),
                      title: name,
                      artwork: URL(string: "https://assets.example/\(name).jpg"))
    }

    private func withSuite(_ body: (String) async throws -> Void) async throws {
        let suite = "pin-tests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        try await body(suite)
    }

    @Test("FR-HOME-02: pinning puts a series at the front of the row")
    func mostRecentlyPinnedFirst() async throws {
        try await withSuite { suite in
            let store = PinStore(suite: suite)

            try await store.pin(Self.series("first"), in: .normal)
            try await store.pin(Self.series("second"), in: .normal)

            #expect(await store.pinned(in: .normal) == [Self.series("second"), Self.series("first")])
        }
    }

    @Test("FR-HOME-02: a series pinned again after being unpinned moves to the front")
    func repinningMovesToTheFront() async throws {
        try await withSuite { suite in
            let store = PinStore(suite: suite)
            try await store.pin(Self.series("first"), in: .normal)
            try await store.pin(Self.series("second"), in: .normal)

            try await store.unpin(Self.series("first").id, in: .normal)
            #expect(await store.pinned(in: .normal) == [Self.series("second")])
            try await store.pin(Self.series("first"), in: .normal)

            #expect(await store.pinned(in: .normal) == [Self.series("first"), Self.series("second")])
        }
    }

    @Test("FR-HOME-02, NFR-REL-04: the pins and their order are still there after a relaunch")
    func pinsSurviveARelaunch() async throws {
        try await withSuite { suite in
            let store = PinStore(suite: suite)
            try await store.pin(Self.series("first"), in: .normal)
            try await store.pin(Self.series("second"), in: .normal)

            let relaunched = PinStore(suite: suite)

            #expect(await relaunched.pinned(in: .normal) == [Self.series("second"), Self.series("first")])
            #expect(await relaunched.isPinned(Self.series("first").id, in: .normal))
        }
    }

    @Test("FR-HOME-03: pinning a series that is already pinned does not make a second tile")
    func pinningTwiceIsOneTile() async throws {
        try await withSuite { suite in
            let store = PinStore(suite: suite)

            try await store.pin(Self.series("same"), in: .normal)
            try await store.pin(Self.series("same"), in: .normal)

            #expect(await store.pinned(in: .normal) == [Self.series("same")])
        }
    }

    @Test("FR-CONTENT-05: a pin keeps the title and image its tile is drawn from")
    func pinKeepsWhatItsTileNeeds() async throws {
        try await withSuite { suite in
            try await PinStore(suite: suite).pin(Self.series("freek"), in: .normal)

            let pinned = try #require(await PinStore(suite: suite).pinned(in: .normal).first)

            #expect(pinned.title == "freek")
            #expect(pinned.artwork == Self.series("freek").artwork)
        }
    }

    @Test("FR-HOME-05: unpinning takes that pin away, stays away, and leaves the others")
    func unpinningRemovesOnePin() async throws {
        try await withSuite { suite in
            let store = PinStore(suite: suite)
            try await store.pin(Self.series("first"), in: .normal)
            try await store.pin(Self.series("second"), in: .normal)

            try await store.unpin(Self.series("second").id, in: .normal)

            #expect(await store.pinned(in: .normal) == [Self.series("first")])
            #expect(await !PinStore(suite: suite).isPinned(Self.series("second").id, in: .normal))
        }
    }

    @Test("FR-HOME-05: unpinning does not touch what else is kept on the television")
    func unpinningLeavesOtherRecords() async throws {
        try await withSuite { suite in
            let history = SearchHistoryStore(suite: suite)
            try await history.remember("fr", picking: PickedItem(.series(Self.series("first"))), in: .normal)
            let store = PinStore(suite: suite)
            try await store.pin(Self.series("first"), in: .normal)

            try await store.unpin(Self.series("first").id, in: .normal)

            #expect(await history.searches(in: .normal).first?.picks.count == 1)
        }
    }

    @Test("FR-MODE-05: a series pinned in one mode is not pinned in the other")
    func modesAreKeptApart() async throws {
        try await withSuite { suite in
            let store = PinStore(suite: suite)

            try await store.pin(Self.series("journaal"), in: .normal)
            try await store.pin(Self.series("bram"), in: .kids)

            #expect(await store.pinned(in: .normal) == [Self.series("journaal")])
            #expect(await store.pinned(in: .kids) == [Self.series("bram")])
            #expect(await !store.isPinned(Self.series("journaal").id, in: .kids))
        }
    }

    @Test("NFR-REL-04: the pins and the search history share one ceiling, and a pin past it is refused")
    func pinsCountTowardsTheCeiling() async throws {
        try await withSuite { suite in
            let history = SearchHistoryStore(suite: suite, ceiling: 300)
            try await history.remember(String(repeating: "x", count: 200), picking: nil, in: .normal)
            let store = PinStore(suite: suite, ceiling: 300)

            await #expect(throws: LocalDataError.full) {
                try await store.pin(Self.series("one too many"), in: .normal)
            }

            #expect(await store.pinned(in: .normal).isEmpty)
        }
    }

    private static let start = Upcoming(Playable(id: EpisodeID(rawValue: "episode-1"),
                                                 title: "Aflevering 1",
                                                 caption: "Afl. 1 • 10m",
                                                 synopsis: nil,
                                                 duration: nil,
                                                 artwork: nil),
                                        in: SeasonID(rawValue: "season-1"))

    @Test("FR-HOME-04: a pin keeps the episode its series starts with, across a relaunch, and loses it with the pin")
    func pinKeepsItsFirstEpisode() async throws {
        try await withSuite { suite in
            let store = PinStore(suite: suite)
            try await store.pin(Self.series("freek"), startingWith: Self.start, in: .normal)
            try await store.pin(Self.series("other"), in: .normal)

            #expect(await PinStore(suite: suite).starts(in: .normal) == [Self.series("freek").id: Self.start])
            #expect(await store.starts(in: .kids).isEmpty)

            try await store.unpin(Self.series("freek").id, in: .normal)

            #expect(await store.starts(in: .normal).isEmpty)
        }
    }

    @Test("NFR-REL-04: pins kept before a first episode was kept with them are still read")
    func olderListIsRead() async throws {
        try await withSuite { suite in
            let older = #"{"series":[{"id":{"rawValue":"freek"},"title":"freek"}]}"#
            UserDefaults(suiteName: suite)?.set(Data(older.utf8), forKey: "local.pins.normal")

            let store = PinStore(suite: suite)

            #expect(await store.pinned(in: .normal).map(\.title) == ["freek"])
            #expect(await store.starts(in: .normal).isEmpty)
        }
    }
}
