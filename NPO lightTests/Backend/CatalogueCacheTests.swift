//
//  CatalogueCacheTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// What NPO answered, kept on the television, and the rules for answering
/// from it. Each test has a directory of its own.
struct CatalogueCacheTests {
    private static let series = StubCatalogue.detail
    private static let season = StubCatalogue.seasons[0].id
    private static let start = Date(timeIntervalSince1970: 1_000_000)

    private func withDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "cache-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    private static func key(_ name: String, _ mode: Mode = .normal) -> CatalogueCache.Key {
        CatalogueCache.Key(kind: .series, identifier: name, mode: mode)
    }

    private static func cached(_ stub: StubCatalogue,
                               in directory: URL,
                               clock: TestClock) -> CachedCatalogue {
        CachedCatalogue(wrapping: stub, cache: CatalogueCache(directory: directory), clock: clock)
    }

    // MARK: The cache

    @Test("FR-CONTENT-04: an answer that was kept is read back, with when NPO gave it, also after a relaunch")
    func answerIsReadBack() async throws {
        try await withDirectory { directory in
            await CatalogueCache(directory: directory).store(Self.series, for: Self.key("freek"), at: Self.start)

            let entry = await CatalogueCache(directory: directory).entry(SeriesDetail.self, for: Self.key("freek"))

            #expect(entry?.value == Self.series)
            #expect(entry?.fetchedAt == Self.start)
        }
    }

    @Test("FR-CONTENT-04: nothing kept, or something that cannot be read, is no answer")
    func unreadableIsNoAnswer() async throws {
        try await withDirectory { directory in
            let cache = CatalogueCache(directory: directory)
            #expect(await cache.entry(SeriesDetail.self, for: Self.key("freek")) == nil)

            // Kept by another version of the app, in another shape.
            await cache.store(["not", "a", "series"], for: Self.key("freek"), at: Self.start)

            #expect(await cache.entry(SeriesDetail.self, for: Self.key("freek")) == nil)
        }
    }

    @Test("FR-CONTENT-04, NFR-PERF-04: the cache holds a fixed number of answers, and drops the oldest")
    func oldestAnswerIsDropped() async throws {
        try await withDirectory { directory in
            let cache = CatalogueCache(directory: directory, entryCeiling: 3)

            for number in 1...5 {
                await cache.store(Self.series, for: Self.key("series-\(number)"),
                                  at: Self.start.addingTimeInterval(TimeInterval(number)))
            }

            #expect(await cache.footprint.entries == 3)
            #expect(await cache.entry(SeriesDetail.self, for: Self.key("series-1")) == nil)
            #expect(await cache.entry(SeriesDetail.self, for: Self.key("series-2")) == nil)
            #expect(await cache.entry(SeriesDetail.self, for: Self.key("series-5")) != nil)
        }
    }

    @Test("NFR-PERF-04: the cache holds a fixed number of bytes, also counting what an earlier launch kept")
    func byteCeilingHolds() async throws {
        try await withDirectory { directory in
            let first = CatalogueCache(directory: directory)
            await first.store(Self.series, for: Self.key("old"), at: Self.start)
            let one = await first.footprint.bytes

            let relaunched = CatalogueCache(directory: directory, byteCeiling: one + one / 2)
            await relaunched.store(Self.series, for: Self.key("new"), at: Self.start.addingTimeInterval(60))

            #expect(await relaunched.footprint.entries == 1)
            #expect(await relaunched.entry(SeriesDetail.self, for: Self.key("new")) != nil)
        }
    }

    @Test("FR-MODE-04, FR-SET-04: an answer belongs to its mode, and erasing a mode forgets that mode's answers only")
    func erasingIsPerMode() async throws {
        try await withDirectory { directory in
            let cache = CatalogueCache(directory: directory)
            await cache.store(Self.series, for: Self.key("freek", .normal), at: Self.start)
            await cache.store(Self.series, for: Self.key("freek", .kids), at: Self.start)

            await cache.erase(.kids)

            #expect(await cache.entry(SeriesDetail.self, for: Self.key("freek", .kids)) == nil)
            #expect(await cache.entry(SeriesDetail.self, for: Self.key("freek", .normal)) != nil)
        }
    }

    @Test("FR-SET-04, NFR-PRIV-04: erasing local data forgets what was browsed in the mode")
    func eraserClearsTheCache() async throws {
        try await withDirectory { directory in
            let cache = CatalogueCache(directory: directory)
            await cache.store(Self.series, for: Self.key("freek"), at: Self.start)
            let suite = "cache-tests-\(UUID().uuidString)"
            defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
            let eraser = LocalDataEraser(progress: ScriptedProgress(), catalogue: cache, suite: suite)

            await eraser.erase([.normal])

            #expect(await CatalogueCache(directory: directory).footprint.entries == 0)
        }
    }

    // MARK: Answering from it

    @Test("FR-CONTENT-04: a page seen a moment ago is answered without asking NPO again")
    func youngAnswerNeedsNoNetwork() async throws {
        try await withDirectory { directory in
            let stub = StubCatalogue()
            let clock = TestClock(now: Self.start)
            let catalogue = Self.cached(stub, in: directory, clock: clock)
            _ = try await catalogue.episodes(of: Self.season, in: .normal)

            clock.advance(by: .seconds(CachedCatalogue.maximumAge - 1))
            let again = try await catalogue.episodes(of: Self.season, in: .normal)

            #expect(again == StubCatalogue.episodes(of: Self.season))
            #expect(stub.seasonRequests == [Self.season])
        }
    }

    @Test("FR-CONTENT-04: an answer older than the maximum age is asked for again, and the new one kept")
    func oldAnswerIsRefreshed() async throws {
        try await withDirectory { directory in
            let changed = Counter()
            let stub = StubCatalogue(season: { season in
                Array(StubCatalogue.episodes(of: season).prefix(changed.increment()))
            })
            let clock = TestClock(now: Self.start)
            let catalogue = Self.cached(stub, in: directory, clock: clock)
            let first = try await catalogue.episodes(of: Self.season, in: .normal)
            #expect(first.count == 1)

            clock.advance(by: .seconds(CachedCatalogue.maximumAge))
            let second = try await catalogue.episodes(of: Self.season, in: .normal)

            #expect(second.count == 2)
            #expect(await catalogue.rememberedEpisodes(of: Self.season, in: .normal)?.count == 2)
        }
    }

    @Test("NFR-REL-01: when NPO cannot be reached, what was seen before is answered, however old")
    func staleAnswerWithoutANetwork() async throws {
        try await withDirectory { directory in
            let clock = TestClock(now: Self.start)
            _ = try await Self.cached(StubCatalogue(), in: directory, clock: clock).series(Self.series.id, in: .normal)
            clock.advance(by: .seconds(7 * 24 * 3600))
            let offline = Self.cached(StubCatalogue(detail: { _ in throw BackendError.unreachable }),
                                      in: directory, clock: clock)

            #expect(try await offline.series(Self.series.id, in: .normal) == Self.series)
        }
    }

    @Test("NFR-REL-02: with nothing kept, a failure is the answer")
    func nothingKeptFails() async throws {
        try await withDirectory { directory in
            let offline = Self.cached(StubCatalogue(detail: { _ in throw BackendError.unreachable }),
                                      in: directory, clock: TestClock(now: Self.start))

            await #expect(throws: BackendError.unreachable) {
                _ = try await offline.series(Self.series.id, in: .normal)
            }
        }
    }

    @Test("FR-CONTENT-05: when NPO no longer has something, what was kept of it is forgotten")
    func goneItemIsForgotten() async throws {
        try await withDirectory { directory in
            let clock = TestClock(now: Self.start)
            _ = try await Self.cached(StubCatalogue(), in: directory, clock: clock).series(Self.series.id, in: .normal)
            clock.advance(by: .seconds(CachedCatalogue.maximumAge))
            let gone = Self.cached(StubCatalogue(detail: { _ in throw BackendError.itemUnavailable }),
                                   in: directory, clock: clock)

            await #expect(throws: BackendError.itemUnavailable) {
                _ = try await gone.series(Self.series.id, in: .normal)
            }
            #expect(await gone.rememberedSeries(Self.series.id, in: .normal) == nil)
        }
    }

    @Test("FR-CONTENT-04: what is kept is there to show at once, without asking, and nothing is before a first answer")
    func rememberedIsThereAtOnce() async throws {
        try await withDirectory { directory in
            let stub = StubCatalogue()
            let catalogue = Self.cached(stub, in: directory, clock: TestClock(now: Self.start))
            let film = EpisodeID(rawValue: "film")
            #expect(await catalogue.rememberedSeries(Self.series.id, in: .normal) == nil)
            #expect(await catalogue.rememberedProgramme(film, in: .normal) == nil)

            _ = try await catalogue.series(Self.series.id, in: .normal)
            _ = try await catalogue.programme(film, in: .normal)

            #expect(await catalogue.rememberedSeries(Self.series.id, in: .normal) == Self.series)
            #expect(await catalogue.rememberedProgramme(film, in: .normal) == StubCatalogue.film(film))
            // The other mode saw nothing.
            #expect(await catalogue.rememberedSeries(Self.series.id, in: .kids) == nil)
        }
    }

    @Test("FR-SEARCH-02: a search is always asked of NPO: its answer is for what was typed just now")
    func searchIsNotKept() async throws {
        try await withDirectory { directory in
            let stub = StubCatalogue()
            let catalogue = Self.cached(stub, in: directory, clock: TestClock(now: Self.start))

            _ = try await catalogue.search(for: "fr", in: .normal)
            _ = try await catalogue.search(for: "fr", in: .normal)

            #expect(stub.searches.count == 2)
        }
    }
}
