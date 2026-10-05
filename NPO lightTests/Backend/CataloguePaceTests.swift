//
//  CataloguePaceTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// How soon a kept answer is asked for again, by what it is about.
struct CataloguePaceTests {
    private static let season = StubCatalogue.seasons[0].id
    private static let start = Date(timeIntervalSince1970: 1_000_000)

    private func withDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "pace-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    private static func cached(_ stub: StubCatalogue,
                               in directory: URL,
                               clock: TestClock) -> CachedCatalogue {
        CachedCatalogue(wrapping: stub, cache: CatalogueCache(directory: directory), clock: clock)
    }

    private static let halfHour: TimeInterval = 30 * 60
    private static let day: TimeInterval = 24 * 60 * 60
    private static let week: TimeInterval = 7 * day

    /// How often the stub was asked for a season after looking at it, then
    /// looking again just before `age` has passed and once more just after.
    private func asks(for season: SeasonID,
                      of detail: SeriesDetail,
                      around age: TimeInterval,
                      in directory: URL) async throws -> [Int] {
        let stub = StubCatalogue(detail: { _ in detail })
        let clock = TestClock(now: Self.start)
        let catalogue = Self.cached(stub, in: directory, clock: clock)
        _ = try await catalogue.series(detail.id, in: .normal)
        _ = try await catalogue.episodes(of: season, in: .normal)
        clock.advance(by: .seconds(age - 1))
        _ = try await catalogue.episodes(of: season, in: .normal)
        let before = stub.seasonRequests.count
        clock.advance(by: .seconds(1))
        _ = try await catalogue.episodes(of: season, in: .normal)
        return [before, stub.seasonRequests.count]
    }

    @Test("FR-CONTENT-04: the three paces are half an hour, a day and a week")
    func paces() {
        #expect(CatalogueCache.Pace.current.age == Self.halfHour)
        #expect(CatalogueCache.Pace.running.age == Self.day)
        #expect(CatalogueCache.Pace.settled.age == Self.week)
    }

    @Test("FR-CONTENT-04: the latest season of a programme followed as it is broadcast is asked for after half an hour")
    func dailyProgrammeIsCurrent() async throws {
        try await withDirectory { directory in
            var daily = StubCatalogue.detail
            daily.listsNewestFirst = true
            // Listed first, so the latest.
            let latest = StubCatalogue.seasons[0].id

            let asked = try await asks(for: latest, of: daily, around: Self.halfHour, in: directory)
            #expect(asked == [1, 2])
        }
    }

    @Test("FR-CONTENT-04: the latest season of any other series is asked for again after a day")
    func latestSeasonIsRunning() async throws {
        try await withDirectory { directory in
            let latest = StubCatalogue.seasons[1].id

            let asked = try await asks(for: latest, of: StubCatalogue.detail, around: Self.day, in: directory)
            #expect(asked == [1, 2])
        }
    }

    @Test("FR-CONTENT-04: an earlier season no longer changes, and is asked for again after a week",
          arguments: [false, true])
    func earlierSeasonIsSettled(listsNewestFirst: Bool) async throws {
        try await withDirectory { directory in
            var detail = StubCatalogue.detail
            detail.listsNewestFirst = listsNewestFirst
            let earlier = listsNewestFirst ? StubCatalogue.seasons[1].id : StubCatalogue.seasons[0].id

            let asked = try await asks(for: earlier, of: detail, around: Self.week, in: directory)
            #expect(asked == [1, 2])
        }
    }

    @Test("FR-CONTENT-04: a series' own page follows the series: half an hour for a daily programme, a day otherwise")
    func seriesPagePace() async throws {
        try await withDirectory { directory in
            var daily = StubCatalogue.detail
            daily.listsNewestFirst = true
            for (detail, age) in [(StubCatalogue.detail, Self.day), (daily, Self.halfHour)] {
                let asked = Counter()
                let stub = StubCatalogue(detail: { _ in
                    asked.increment()
                    return detail
                })
                let clock = TestClock(now: Self.start)
                let catalogue = Self.cached(stub, in: directory.appending(path: "\(age)"), clock: clock)
                _ = try await catalogue.series(detail.id, in: .normal)

                clock.advance(by: .seconds(age - 1))
                _ = try await catalogue.series(detail.id, in: .normal)
                #expect(asked.value == 1)

                clock.advance(by: .seconds(1))
                _ = try await catalogue.series(detail.id, in: .normal)
                #expect(asked.value == 2)
            }
        }
    }

    @Test("FR-CONTENT-04: a programme's page is asked for again after a week")
    func programmePageIsSettled() async throws {
        try await withDirectory { directory in
            let asked = Counter()
            let stub = StubCatalogue(programme: { id in
                asked.increment()
                return StubCatalogue.film(id)
            })
            let clock = TestClock(now: Self.start)
            let catalogue = Self.cached(stub, in: directory, clock: clock)
            let film = EpisodeID(rawValue: "film")
            _ = try await catalogue.programme(film, in: .normal)

            clock.advance(by: .seconds(Self.week - 1))
            _ = try await catalogue.programme(film, in: .normal)
            #expect(asked.value == 1)

            clock.advance(by: .seconds(1))
            _ = try await catalogue.programme(film, in: .normal)
            #expect(asked.value == 2)
        }
    }

    @Test("FR-CONTENT-04: a season keeps its pace across a relaunch, when its series has not been looked at yet")
    func paceIsKeptWithTheAnswer() async throws {
        try await withDirectory { directory in
            let earlier = StubCatalogue.seasons[0].id
            let clock = TestClock(now: Self.start)
            let first = Self.cached(StubCatalogue(), in: directory, clock: clock)
            _ = try await first.series(StubCatalogue.detail.id, in: .normal)
            _ = try await first.episodes(of: earlier, in: .normal)

            // Another launch, a day later, straight to the season: from a
            // tile on the home page, say.
            clock.advance(by: .seconds(Self.day))
            let stub = StubCatalogue()
            _ = try await Self.cached(stub, in: directory, clock: clock).episodes(of: earlier, in: .normal)

            #expect(stub.seasonRequests.isEmpty)
        }
    }

    @Test("FR-CONTENT-04: a season whose series is not known is asked for again after half an hour")
    func unknownSeasonIsCurrent() async throws {
        try await withDirectory { directory in
            let stub = StubCatalogue()
            let clock = TestClock(now: Self.start)
            let catalogue = Self.cached(stub, in: directory, clock: clock)
            _ = try await catalogue.episodes(of: Self.season, in: .normal)

            clock.advance(by: .seconds(Self.halfHour))
            _ = try await catalogue.episodes(of: Self.season, in: .normal)

            #expect(stub.seasonRequests.count == 2)
        }
    }
}
