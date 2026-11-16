//
//  NewEpisodesTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// A series that was watched to its end, and what its tile does when NPO has
/// more of it.
@MainActor
struct NewEpisodesTests {
    nonisolated private static let series = StubCatalogue.results.series[0]
    nonisolated private static let first = StubCatalogue.seasons[0].id
    nonisolated private static let second = StubCatalogue.seasons[1].id
    nonisolated private static let start = Date(timeIntervalSince1970: 0)

    /// The series while it had one season.
    nonisolated private static let oneSeason = SeriesDetail(id: series.id,
                                                            title: series.title,
                                                            synopsis: nil,
                                                            artwork: nil,
                                                            seasons: [StubCatalogue.seasons[0]])

    /// A programme with a season for each year, the latest first.
    nonisolated private static let daily = SeriesDetail(id: series.id,
                                                        title: series.title,
                                                        synopsis: nil,
                                                        artwork: nil,
                                                        seasons: StubCatalogue.seasons.reversed(),
                                                        listsNewestFirst: true)

    private let progress = ScriptedProgress()
    private let history = ScriptedWatchHistory()
    private let pins = ScriptedPins()

    private func model(_ catalogue: StubCatalogue) -> HomeModel {
        HomeModel(pins: pins,
                  watched: WatchedState(progress: progress, history: history, later: ScriptedWatchLater()),
                  catalogue: catalogue,
                  clock: TestClock(now: Self.start),
                  mode: .normal)
    }

    /// Three episodes where there were two.
    nonisolated private static func grown(_ season: SeasonID) -> [Playable] {
        StubCatalogue.episodes(of: season) + [Playable(id: EpisodeID(rawValue: "\(season.rawValue)-3"),
                                                       title: "Nieuw", caption: nil, synopsis: nil, duration: nil,
                                                       artwork: nil)]
    }

    /// The series was watched to the end of its first season, which was all
    /// there was.
    private func watchedToItsEnd() async {
        for episode in StubCatalogue.episodes(of: Self.first) {
            await finished(episode.id)
        }
        var entry = WatchedEntry(series: Self.series, next: nil, playedAt: Self.start)
        entry.finishedAt = Self.start
        await history.record(entry, in: .normal)
    }

    private func finished(_ id: EpisodeID) async {
        await progress.keep(PlaybackProgress(id: id, offset: nil, finishedAt: Self.start, updatedAt: Self.start),
                            in: .normal)
    }

    @Test("FR-HOME-14: a pinned series watched to its end offers the episode that was added to its season")
    func pinnedTileOffersTheAddedEpisode() async throws {
        await pins.pin(Self.series, in: .normal)
        await watchedToItsEnd()
        let model = model(StubCatalogue(detail: { _ in Self.oneSeason }, season: { Self.grown($0) }))

        await model.refresh()
        #expect(try #require(model.pinned.first).state == .finished)
        await model.catchUp()

        let added = Upcoming(Self.grown(Self.first)[2], in: Self.first)
        #expect(try #require(model.pinned.first).state == .continues(added, fraction: nil))
    }

    @Test("FR-HOME-14, FR-CONTENT-02: a series watched to its end offers the first episode of a season added since")
    func tileOffersTheSeasonAddedSince() async throws {
        await watchedToItsEnd()
        let model = model(StubCatalogue())

        await model.refresh()
        await model.catchUp()

        let added = Upcoming(StubCatalogue.episodes(of: Self.second)[0], in: Self.second)
        #expect(try #require(model.continuing.first).state == .continues(added, fraction: nil))
    }

    @Test("FR-HOME-14, FR-HOME-04: a programme listed latest first offers its latest episode once that is a new one")
    func dailyProgrammeOffersItsLatest() async throws {
        await pins.pin(Self.series, in: .normal)
        await watchedToItsEnd()
        let model = model(StubCatalogue(detail: { _ in Self.daily }))

        await model.refresh()
        await model.catchUp()

        let latest = Upcoming(StubCatalogue.episodes(of: Self.second)[1], in: Self.second)
        #expect(try #require(model.pinned.first).state == .continues(latest, fraction: nil))
    }

    @Test("FR-HOME-14: a programme listed latest first whose latest episode was watched still says so")
    func dailyProgrammeWithNothingNewStays() async throws {
        await pins.pin(Self.series, in: .normal)
        await watchedToItsEnd()
        await finished(StubCatalogue.episodes(of: Self.second)[1].id)
        let model = model(StubCatalogue(detail: { _ in Self.daily }))

        await model.refresh()
        await model.catchUp()

        #expect(try #require(model.pinned.first).state == .finished)
    }

    @Test("FR-HOME-14: a series with nothing added still says that everything was watched")
    func nothingAddedChangesNothing() async throws {
        await pins.pin(Self.series, in: .normal)
        await watchedToItsEnd()
        let model = model(StubCatalogue(detail: { _ in Self.oneSeason }))

        await model.refresh()
        await model.catchUp()

        #expect(try #require(model.pinned.first).state == .finished)
    }

    @Test("FR-HOME-14, FR-HOME-08: finding an episode leaves when the series was played, and what was hidden, alone")
    func tileKeepsItsPlace() async throws {
        await pins.pin(Self.series, in: .normal)
        await watchedToItsEnd()
        await history.hide(Self.series.id, in: .normal)
        let model = model(StubCatalogue())

        await model.refresh()
        await model.catchUp()

        let entry = try #require(await history.entry(for: Self.series.id, in: .normal))
        #expect(entry.next?.id == StubCatalogue.episodes(of: Self.second)[0].id)
        #expect(entry.finishedAt == nil)
        #expect(entry.playedAt == Self.start)
        #expect(entry.isHidden)
        #expect(model.continuing.isEmpty)
    }

    @Test("FR-HOME-14: when NPO cannot be reached the tile stays as it was")
    func unreachableChangesNothing() async throws {
        await pins.pin(Self.series, in: .normal)
        await watchedToItsEnd()
        let model = model(StubCatalogue(detail: { _ in throw BackendError.unreachable },
                                        season: { _ in throw BackendError.unreachable }))

        await model.refresh()
        await model.catchUp()

        #expect(try #require(model.pinned.first).state == .finished)
    }

    @Test("FR-HOME-14: NPO is not asked about a series whose tile offers an episode")
    func continuingSeriesIsNotAskedAbout() async {
        let next = Upcoming(StubCatalogue.episodes(of: Self.first)[1], in: Self.first)
        await pins.pin(Self.series, in: .normal)
        await history.record(WatchedEntry(series: Self.series, next: next, playedAt: Self.start), in: .normal)
        let catalogue = StubCatalogue()
        let model = model(catalogue)

        await model.refresh()
        await model.catchUp()

        #expect(catalogue.seasonRequests.isEmpty)
    }
}
