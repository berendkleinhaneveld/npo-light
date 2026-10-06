//
//  ProgressStoreTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// The positions as they are kept. Each test has a directory and a suite of
/// defaults of its own, and removes them again.
struct ProgressStoreTests {
    private static func progress(_ name: String,
                                 at offset: TimeInterval? = 100,
                                 updated: TimeInterval = 0) -> PlaybackProgress {
        PlaybackProgress(id: EpisodeID(rawValue: name),
                         offset: offset,
                         finishedAt: nil,
                         updatedAt: Date(timeIntervalSince1970: updated))
    }

    /// A directory standing in for `Caches`, and a suite standing in for the
    /// app's defaults.
    private func withStorage(_ body: (URL, String) async throws -> Void) async throws {
        let name = "progress-tests-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appending(path: name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
        try await body(directory, name)
    }

    @Test("FR-PLAY-13: what NPO was last seen to have is kept with the position, across launches")
    func whatNPOSaidIsKept() async throws {
        try await withStorage { directory, suite in
            var position = Self.progress("one", at: 300)
            position.shared = 290.5
            try await ProgressStore.open(in: directory, suite: suite).note(position, in: .normal)

            let reopened = ProgressStore.open(in: directory, suite: suite)

            #expect(await reopened.progress(of: position.id, in: .normal)?.shared == 290.5)
            #expect(!reopened.wasReset)
        }
    }

    @Test("FR-PLAY-03: a position that was written is read back, and a later one replaces it")
    func positionIsReadBack() async throws {
        try await withStorage { directory, suite in
            let store = ProgressStore.open(in: directory, suite: suite)
            #expect(await store.progress(of: EpisodeID(rawValue: "one"), in: .normal) == nil)

            try await store.note(Self.progress("one", at: 10), in: .normal)
            try await store.note(Self.progress("one", at: 20, updated: 5), in: .normal)

            #expect(await store.progress(of: EpisodeID(rawValue: "one"), in: .normal)
                    == Self.progress("one", at: 20, updated: 5))
        }
    }

    @Test("FR-CONTENT-08, FR-MODE-05: a season's positions are read in one question, for one mode")
    func positionsAreReadTogether() async throws {
        try await withStorage { directory, suite in
            let store = ProgressStore.open(in: directory, suite: suite)
            try await store.note(Self.progress("one", at: 10), in: .normal)
            try await store.note(Self.progress("two", at: 20), in: .normal)
            try await store.note(Self.progress("three", at: 30), in: .kids)
            let ids = ["one", "two", "three", "four"].map(EpisodeID.init(rawValue:))

            let read = await store.progress(of: ids, in: .normal)

            #expect(read == [ids[0]: Self.progress("one", at: 10), ids[1]: Self.progress("two", at: 20)])
        }
    }

    @Test("FR-HOME-06: the length of what was played is kept with its position")
    func durationIsStored() async throws {
        try await withStorage { directory, suite in
            var progress = Self.progress("one", at: 150)
            progress.duration = 600
            try await ProgressStore.open(in: directory, suite: suite).keep(progress, in: .normal)

            let read = await ProgressStore.open(in: directory, suite: suite).progress(of: progress.id, in: .normal)

            #expect(read?.fraction == 0.25)
        }
    }

    @Test("ADR 0012: a finish and a position are kept as two facts in one record")
    func finishAndOffsetAreIndependent() async throws {
        try await withStorage { directory, suite in
            let store = ProgressStore.open(in: directory, suite: suite)
            var progress = Self.progress("one", at: nil)
            progress.finishedAt = Date(timeIntervalSince1970: 50)

            try await store.keep(progress, in: .normal)

            let read = try #require(await store.progress(of: progress.id, in: .normal))
            #expect(read.offset == nil)
            #expect(read.finishedAt == Date(timeIntervalSince1970: 50))
        }
    }

    @Test("FR-MODE-05: the same episode has a position of its own in each mode")
    func modesAreKeptApart() async throws {
        try await withStorage { directory, suite in
            let store = ProgressStore.open(in: directory, suite: suite)

            try await store.keep(Self.progress("one", at: 10), in: .normal)
            try await store.keep(Self.progress("one", at: 99), in: .kids)

            #expect(await store.progress(of: EpisodeID(rawValue: "one"), in: .normal)?.offset == 10)
            #expect(await store.progress(of: EpisodeID(rawValue: "one"), in: .kids)?.offset == 99)
        }
    }

    @Test("FR-PLAY-03, NFR-REL-04: positions are still there after a relaunch, including one written mid-playback")
    func positionsSurviveARelaunch() async throws {
        try await withStorage { directory, suite in
            let store = ProgressStore.open(in: directory, suite: suite)
            try await store.keep(Self.progress("rested", at: 10), in: .normal)
            try await store.note(Self.progress("playing", at: 20), in: .normal)

            let relaunched = ProgressStore.open(in: directory, suite: suite)

            #expect(await relaunched.progress(of: EpisodeID(rawValue: "rested"), in: .normal)?.offset == 10)
            #expect(await relaunched.progress(of: EpisodeID(rawValue: "playing"), in: .normal)?.offset == 20)
            #expect(!relaunched.wasReset)
        }
    }

    @Test("NFR-REL-04: after tvOS deleted the store, the positions that were kept are there, and nothing is reset")
    func evictedStoreIsRebuiltFromTheCopy() async throws {
        try await withStorage { directory, suite in
            let store = ProgressStore.open(in: directory, suite: suite)
            try await store.keep(Self.progress("film", at: 1800), in: .normal)
            try await store.keep(Self.progress("bram", at: 60), in: .kids)
            // Only in the store: what a hard stop mid-episode, then an
            // eviction, can cost.
            try await store.note(Self.progress("playing", at: 20), in: .normal)

            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                try FileManager.default.removeItem(at: file)
            }
            let rebuilt = ProgressStore.open(in: directory, suite: suite)

            #expect(await rebuilt.progress(of: EpisodeID(rawValue: "film"), in: .normal)
                    == Self.progress("film", at: 1800))
            #expect(await rebuilt.progress(of: EpisodeID(rawValue: "bram"), in: .kids)?.offset == 60)
            #expect(await rebuilt.progress(of: EpisodeID(rawValue: "bram"), in: .normal) == nil)
            #expect(await rebuilt.progress(of: EpisodeID(rawValue: "playing"), in: .normal) == nil)
            #expect(!rebuilt.wasReset)
        }
    }

    @Test("NFR-REL-04: when the copy is full its oldest positions make room, and the store keeps them all")
    func copyDropsItsOldest() async throws {
        try await withStorage { _, suite in
            let container = ProgressStore.inMemory().modelContainer
            let store = ProgressStore(container: container, isNew: false, suite: suite, copyBudget: 1000)

            for number in 1...40 {
                try await store.keep(Self.progress("episode \(number)", updated: TimeInterval(number)), in: .normal)
            }

            let copy = try #require(LocalDefaults(suite: suite).value(PositionCopy.self, for: .positions, in: .normal))
            #expect(LocalDefaults(suite: suite).size <= 1000)
            #expect(copy.positions.first?.id == EpisodeID(rawValue: "episode 40"))
            #expect(copy.positions.count < 40)
            #expect(!copy.positions.contains { $0.id == EpisodeID(rawValue: "episode 1") })
            #expect(await store.progress(of: EpisodeID(rawValue: "episode 1"), in: .normal) != nil)
        }
    }

    @Test("NFR-REL-04: the copy never takes the defaults past their ceiling, and what the family chose comes first")
    func copyYieldsToTheLists() async throws {
        try await withStorage { _, suite in
            try await SearchHistoryStore(suite: suite, ceiling: 600)
                .remember(String(repeating: "x", count: 400), picking: nil, in: .normal)
            let container = ProgressStore.inMemory().modelContainer
            let store = ProgressStore(container: container, isNew: false, suite: suite, ceiling: 600)

            for number in 1...10 {
                try await store.keep(Self.progress("episode \(number)"), in: .normal)
            }

            let defaults = LocalDefaults(suite: suite, ceiling: 600)
            #expect(defaults.size <= 600)
            #expect(await SearchHistoryStore(suite: suite).searches(in: .normal).count == 1)
            #expect(await store.progress(of: EpisodeID(rawValue: "episode 10"), in: .normal) != nil)
        }
    }

    @Test("NFR-REL-05: a store that cannot be read is started over instead of crashing, and says so")
    func unreadableStoreIsReset() async throws {
        try await withStorage { directory, suite in
            try Data("this is not a database".utf8).write(to: directory.appending(path: "positions.store"))

            let store = ProgressStore.open(in: directory, suite: suite)

            #expect(store.wasReset)
            try await store.keep(Self.progress("one", at: 10), in: .normal)
            #expect(await store.progress(of: EpisodeID(rawValue: "one"), in: .normal)?.offset == 10)
        }
    }

    @Test("NFR-PERF-05: a position asked for from the main actor is read off it")
    @MainActor
    func storeIsOffTheMainActor() async throws {
        try await withStorage { directory, suite in
            let store: any ProgressKeeping = ProgressStore.open(in: directory, suite: suite)

            try await store.keep(Self.progress("one", at: 10), in: .normal)

            #expect(await store.progress(of: EpisodeID(rawValue: "one"), in: .normal)?.offset == 10)
        }
    }
}
