//
//  LocalDataEraserTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// Erasing what is kept, over the real stores in a suite and a directory of
/// the test's own.
struct LocalDataEraserTests {
    private static let series = SeriesSummary(id: ItemID(rawValue: "series"), title: "Serie", artwork: nil)
    private static let film = Playable(id: EpisodeID(rawValue: "film"), title: "Film", caption: nil, synopsis: nil,
                                       duration: nil, artwork: nil)

    private struct Stores {
        let pins: PinStore
        let history: WatchHistoryStore
        let later: WatchLaterStore
        let searches: SearchHistoryStore
        let progress: ProgressStore
        let eraser: LocalDataEraser

        init(directory: URL, suite: String) {
            pins = PinStore(suite: suite)
            history = WatchHistoryStore(suite: suite)
            later = WatchLaterStore(suite: suite)
            searches = SearchHistoryStore(suite: suite)
            progress = ProgressStore.open(in: directory, suite: suite)
            eraser = LocalDataEraser(progress: progress, suite: suite)
        }

        /// One of everything, in `mode`.
        func fill(_ mode: Mode) async throws {
            try await pins.pin(series, in: mode)
            try await history.record(WatchedEntry(single: film, playedAt: Date(timeIntervalSince1970: 0)), in: mode)
            try await later.save(SavedItem(film, origin: .single), in: mode)
            try await searches.remember("fr", picking: nil, in: mode)
            try await progress.keep(PlaybackProgress(id: film.id, offset: 60, finishedAt: nil,
                                                     updatedAt: Date(timeIntervalSince1970: 0)),
                                    in: mode)
        }

        /// How many of the five kinds of record `mode` still has.
        func kinds(in mode: Mode) async -> Int {
            var count = 0
            if await !pins.pinned(in: mode).isEmpty { count += 1 }
            if await !history.entries(in: mode).isEmpty { count += 1 }
            if await !later.saved(in: mode).isEmpty { count += 1 }
            if await !searches.searches(in: mode).isEmpty { count += 1 }
            if await progress.progress(of: film.id, in: mode) != nil { count += 1 }
            return count
        }
    }

    private func withStorage(_ body: (URL, String) async throws -> Void) async throws {
        let name = "eraser-tests-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appending(path: name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
        try await body(directory, name)
    }

    @Test("FR-SET-04, FR-LATER-01, NFR-PRIV-04: erasing a mode leaves no pin, entry, saved item, search or position")
    func erasingRemovesEverything() async throws {
        try await withStorage { directory, suite in
            let stores = Stores(directory: directory, suite: suite)
            try await stores.fill(.normal)
            #expect(await stores.kinds(in: .normal) == 5)

            await stores.eraser.erase([.normal])

            #expect(await stores.kinds(in: .normal) == 0)
        }
    }

    @Test("FR-SET-04, FR-LATER-10: erasing one mode leaves the other mode's data untouched")
    func otherModeIsUntouched() async throws {
        try await withStorage { directory, suite in
            let stores = Stores(directory: directory, suite: suite)
            try await stores.fill(.normal)
            try await stores.fill(.kids)

            await stores.eraser.erase([.kids])

            #expect(await stores.kinds(in: .kids) == 0)
            #expect(await stores.kinds(in: .normal) == 5)
        }
    }

    @Test("FR-SET-04: both modes can be erased at once")
    func bothModesAtOnce() async throws {
        try await withStorage { directory, suite in
            let stores = Stores(directory: directory, suite: suite)
            try await stores.fill(.normal)
            try await stores.fill(.kids)

            await stores.eraser.erase([.normal, .kids])

            #expect(await stores.kinds(in: .normal) == 0)
            #expect(await stores.kinds(in: .kids) == 0)
        }
    }

    @Test("NFR-PRIV-04: what was erased does not come back after a relaunch, nor from the copy when the store is gone")
    func erasedStaysErased() async throws {
        try await withStorage { directory, suite in
            let stores = Stores(directory: directory, suite: suite)
            try await stores.fill(.normal)
            await stores.eraser.erase([.normal])

            #expect(await Stores(directory: directory, suite: suite).kinds(in: .normal) == 0)

            // tvOS emptied Caches: the store is rebuilt from the copy.
            let elsewhere = directory.appending(path: "evicted")
            try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
            #expect(await Stores(directory: elsewhere, suite: suite).kinds(in: .normal) == 0)
        }
    }

    @Test("FR-SET-04: the mode and the timings are settings, and erasing data leaves them")
    func settingsSurviveErasing() async throws {
        try await withStorage { directory, suite in
            let stores = Stores(directory: directory, suite: suite)
            StoredMode(suite: suite).mode = .kids
            StoredTimings(suite: suite).keep(15, for: .kidsPause)

            await stores.eraser.erase([.normal, .kids])

            #expect(StoredMode(suite: suite).mode == .kids)
            #expect(StoredTimings(suite: suite).timings[.kidsPause] == 15)
        }
    }
}
