//
//  SeriesWatchedTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// What a series' page shows of what was watched, and what its main action
/// plays.
@MainActor
struct SeriesWatchedTests {
    private static let series = StubCatalogue.results.series[0]
    private static let first = StubCatalogue.seasons[0].id
    private static let second = StubCatalogue.seasons[1].id

    private let progress = ScriptedProgress()
    private let history = ScriptedWatchHistory()

    private func model(_ catalogue: StubCatalogue = StubCatalogue()) -> SeriesDetailModel {
        SeriesDetailModel(summary: Self.series,
                          catalogue: catalogue,
                          pins: ScriptedPins(),
                          watched: WatchedState(progress: progress, history: history),
                          mode: .normal)
    }

    private func loaded(_ catalogue: StubCatalogue = StubCatalogue()) async -> SeriesDetailModel {
        let model = model(catalogue)
        await model.load()
        await model.pending?.value
        return model
    }

    private static func episode(_ number: Int, of season: SeasonID) -> Playable {
        StubCatalogue.episodes(of: season)[number - 1]
    }

    private func continuing(with episode: Playable?, in season: SeasonID) async {
        await history.record(WatchedEntry(series: Self.series,
                                          next: episode.map { Upcoming($0, in: season) },
                                          playedAt: Date(timeIntervalSince1970: 0)),
                             in: .normal)
    }

    private func stopped(_ episode: Playable, at offset: TimeInterval?, finished: Bool = false) async {
        await progress.keep(PlaybackProgress(id: episode.id,
                                             offset: offset,
                                             finishedAt: finished ? Date(timeIntervalSince1970: 0) : nil,
                                             updatedAt: Date(timeIntervalSince1970: 0)),
                            in: .normal)
    }

    @Test("FR-CONTENT-03, FR-HOME-04: with nothing watched the main action plays the first episode, from the start")
    func unwatchedSeriesPlaysTheFirst() async {
        let model = await loaded()

        #expect(model.primary == .init(episode: Self.episode(1, of: Self.first), season: Self.first, resumes: false))
        #expect(!model.isFullyWatched)
    }

    @Test("FR-CONTENT-03: with an episode stopped halfway the main action resumes that episode")
    func partlyWatchedResumes() async {
        let episode = Self.episode(2, of: Self.first)
        await continuing(with: episode, in: Self.first)
        await stopped(episode, at: 300)

        let model = await loaded()

        #expect(model.primary == .init(episode: episode, season: Self.first, resumes: true))
    }

    @Test("FR-CONTENT-03, FR-HOME-04: after episode n the main action plays episode n+1, from the start")
    func playsTheNextUnwatched() async {
        await stopped(Self.episode(1, of: Self.first), at: nil, finished: true)
        await continuing(with: Self.episode(2, of: Self.first), in: Self.first)

        let model = await loaded()

        #expect(model.primary?.episode == Self.episode(2, of: Self.first))
        #expect(model.primary?.resumes == false)
    }

    @Test("FR-CONTENT-07: the page opens on the season that holds the episode the main action plays")
    func opensOnTheContinuedSeason() async {
        let catalogue = StubCatalogue()
        await continuing(with: Self.episode(1, of: Self.second), in: Self.second)

        let model = await loaded(catalogue)

        #expect(model.shownSeason == Self.second)
        #expect(model.primary?.season == Self.second)
        #expect(catalogue.seasonRequests == [Self.second])
    }

    @Test("FR-CONTENT-07, FR-HOME-04: a fully watched series says so, opens on its first season, and offers no play")
    func fullyWatchedSeries() async {
        await continuing(with: nil, in: Self.second)

        let model = await loaded()

        #expect(model.isFullyWatched)
        #expect(model.primary == nil)
        #expect(model.shownSeason == Self.first)
    }

    @Test("FR-CONTENT-07: a series that continues in a season NPO no longer lists opens on the first")
    func goneSeasonOpensOnTheFirst() async {
        await continuing(with: Self.episode(1, of: Self.first), in: SeasonID(rawValue: "gone"))

        let model = await loaded()

        #expect(model.shownSeason == Self.first)
        #expect(model.primary?.episode == Self.episode(1, of: Self.first))
    }

    @Test("FR-CONTENT-08: each episode in the list says whether it was started or watched")
    func episodesShowTheirWatchedState() async {
        await stopped(Self.episode(1, of: Self.first), at: nil, finished: true)
        await stopped(Self.episode(2, of: Self.first), at: 120)

        let model = await loaded()
        #expect(model.watched(Self.episode(1, of: Self.first).id) == .finished)
        #expect(model.watched(Self.episode(2, of: Self.first).id) == .started)

        model.show(Self.second)
        await model.pending?.value

        #expect(model.watched(Self.episode(1, of: Self.second).id) == .notStarted)
    }

    @Test("FR-PLAY-02: an episode being watched again still shows as watched")
    func rewatchingStaysWatched() async {
        await stopped(Self.episode(1, of: Self.first), at: 60, finished: true)

        let model = await loaded()

        #expect(model.watched(Self.episode(1, of: Self.first).id) == .finished)
    }

    @Test("FR-MODE-05: what the other mode watched is not shown")
    func otherModeIsNotShown() async {
        let episode = Self.episode(1, of: Self.first)
        await progress.keep(PlaybackProgress(id: episode.id, offset: 60, finishedAt: nil, updatedAt: .now), in: .kids)

        let model = await loaded()

        #expect(model.watched(episode.id) == .notStarted)
    }

    @Test("FR-HOME-10: coming back from the player shows what was just watched, without leaving the season")
    func readsAgainAfterPlayback() async {
        let model = await loaded()
        model.show(Self.second)
        await model.pending?.value

        // What playing the first season's first episode to its end leaves.
        await stopped(Self.episode(1, of: Self.first), at: nil, finished: true)
        await continuing(with: Self.episode(2, of: Self.first), in: Self.first)
        await model.readWatched()

        #expect(model.watched(Self.episode(1, of: Self.first).id) == .finished)
        #expect(model.primary?.episode == Self.episode(2, of: Self.first))
        #expect(model.shownSeason == Self.second)
    }

    @Test("FR-PLAY-09: an episode played from the page says where in the series it is")
    func requestCarriesThePlace() async {
        let model = await loaded()
        model.show(Self.second)
        await model.pending?.value
        let episode = Self.episode(1, of: Self.second)

        let listed = model.request(for: episode)
        let named = model.request(for: Self.episode(1, of: Self.first), in: Self.first)

        #expect(listed.playable == episode)
        #expect(listed.origin == .series(SeriesPlace(series: Self.series, season: Self.second)))
        #expect(named.origin == .series(SeriesPlace(series: Self.series, season: Self.first)))
    }

    // MARK: A programme listed latest season first

    private func newestFirst() async -> SeriesDetailModel {
        var detail = StubCatalogue.detail
        detail.listsNewestFirst = true
        return await loaded(StubCatalogue(detail: { [detail] _ in detail }))
    }

    @Test("FR-HOME-04: a programme listed latest season first starts with its latest episode")
    func dailyProgrammeOffersTheLatest() async {
        let model = await newestFirst()

        // The first season listed is the latest, and its last episode the newest.
        #expect(model.primary == .init(episode: Self.episode(2, of: Self.first), season: Self.first, resumes: false))
    }

    @Test("FR-HOME-04: a daily programme still continues with an episode that was started")
    func dailyProgrammeContinues() async {
        let episode = Self.episode(1, of: Self.second)
        await continuing(with: episode, in: Self.second)
        await stopped(episode, at: 90)

        let model = await newestFirst()

        #expect(model.primary == .init(episode: episode, season: Self.second, resumes: true))
    }

    @Test("FR-HOME-04: with the latest episode watched, a daily programme has nothing to offer until a newer one comes")
    func dailyProgrammeWatchedToTheLatest() async {
        await continuing(with: nil, in: Self.first)
        await stopped(Self.episode(2, of: Self.first), at: nil, finished: true)

        let model = await newestFirst()

        #expect(model.primary == nil)
        #expect(model.isFullyWatched)
    }

    @Test("FR-HOME-04: a newer episode than the last one watched is offered, though nothing was left before")
    func dailyProgrammeOffersTheNewOne() async {
        // Finished when episode 1 was the latest; episode 2 came since.
        await continuing(with: nil, in: Self.first)
        await stopped(Self.episode(1, of: Self.first), at: nil, finished: true)

        let model = await newestFirst()

        #expect(model.primary?.episode == Self.episode(2, of: Self.first))
        #expect(!model.isFullyWatched)
    }
}
