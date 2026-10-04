//
//  SeriesDetailModelTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

@MainActor
struct SeriesDetailModelTests {
    nonisolated private static let first = StubCatalogue.seasons[0].id
    nonisolated private static let second = StubCatalogue.seasons[1].id

    private func model(_ catalogue: StubCatalogue) -> SeriesDetailModel {
        SeriesDetailModel(summary: StubCatalogue.results.series[0], catalogue: catalogue, mode: .normal)
    }

    @Test("FR-CONTENT-07: the page opens on a season and shows that season's episodes only")
    func opensOnOneSeason() async {
        let catalogue = StubCatalogue()
        let model = model(catalogue)
        #expect(model.page == .loading)

        await model.load()
        await model.pending?.value

        #expect(model.page == .loaded(StubCatalogue.detail))
        #expect(model.shownSeason == Self.first)
        #expect(model.episodes == .loaded(StubCatalogue.episodes(of: Self.first)))
        #expect(catalogue.seasonRequests == [Self.first])
    }

    @Test("FR-CONTENT-07: the picker lists every season in order, and moving along it changes the season shown")
    func pickerChangesTheSeason() async {
        let model = model(StubCatalogue())
        await model.load()
        await model.pending?.value
        #expect(model.pickerSeasons == StubCatalogue.seasons)

        model.show(Self.second)
        #expect(model.shownSeason == Self.second)
        #expect(model.episodes == .loading)
        await model.pending?.value

        #expect(model.episodes == .loaded(StubCatalogue.episodes(of: Self.second)))
    }

    @Test("FR-CONTENT-07: a series with a single season shows no picker")
    func singleSeasonHasNoPicker() async {
        let single = SeriesDetail(id: StubCatalogue.detail.id,
                                  title: StubCatalogue.detail.title,
                                  synopsis: nil,
                                  artwork: nil,
                                  seasons: [StubCatalogue.seasons[0]])
        let model = model(StubCatalogue(detail: { _ in single }))

        await model.load()
        await model.pending?.value

        #expect(model.pickerSeasons.isEmpty)
        #expect(model.episodes == .loaded(StubCatalogue.episodes(of: Self.first)))
    }

    @Test("FR-CONTENT-07: episodes that arrive for a season focus has left are not shown")
    func lateSeasonIsDiscarded() async {
        let reached = Gate()
        let release = Gate()
        let catalogue = StubCatalogue(season: { season in
            if season == Self.first {
                reached.open()
                await release.wait()
            }
            return StubCatalogue.episodes(of: season)
        })
        let model = model(catalogue)
        await model.load()
        let superseded = model.pending
        await reached.wait()

        model.show(Self.second)
        await model.pending?.value
        release.open()
        await superseded?.value

        #expect(model.shownSeason == Self.second)
        #expect(model.episodes == .loaded(StubCatalogue.episodes(of: Self.second)))
    }

    @Test("FR-CONTENT-07: going back to a season already seen does not ask NPO again")
    func seenSeasonIsNotRefetched() async {
        let catalogue = StubCatalogue()
        let model = model(catalogue)
        await model.load()
        await model.pending?.value
        model.show(Self.second)
        await model.pending?.value

        model.show(Self.first)

        #expect(model.episodes == .loaded(StubCatalogue.episodes(of: Self.first)))
        #expect(catalogue.seasonRequests == [Self.first, Self.second])
    }

    @Test("FR-CONTENT-08: the episode with focus is the one previewed, and the first before any has it")
    func focusedEpisodeIsPreviewed() async {
        let model = model(StubCatalogue())
        await model.load()
        await model.pending?.value
        let episodes = StubCatalogue.episodes(of: Self.first)
        #expect(model.previewed == episodes[0])

        model.focus(episodes[1].id)
        #expect(model.previewed == episodes[1])

        // Another season: the preview does not keep an episode that is no
        // longer in the list.
        model.show(Self.second)
        await model.pending?.value

        #expect(model.previewed == StubCatalogue.episodes(of: Self.second)[0])
    }

    @Test("FR-CONTENT-05: a series NPO no longer has says so, rather than failing")
    func goneSeriesIsUnavailable() async {
        let model = model(StubCatalogue(detail: { _ in throw BackendError.itemUnavailable }))

        await model.load()

        #expect(model.page == .unavailable)
    }

    @Test("NFR-REL-02: a series that could not be fetched can be retried without leaving the page")
    func failedSeriesCanBeRetried() async {
        let attempts = Counter()
        let model = model(StubCatalogue(detail: { _ in
            if attempts.increment() == 1 { throw BackendError.unreachable }
            return StubCatalogue.detail
        }))

        await model.load()
        #expect(model.page == .failed)

        await model.load()

        #expect(model.page == .loaded(StubCatalogue.detail))
    }

    @Test("NFR-REL-02: a season that could not be fetched can be retried in place")
    func failedSeasonCanBeRetried() async {
        let attempts = Counter()
        let model = model(StubCatalogue(season: { season in
            if attempts.increment() == 1 { throw BackendError.unreachable }
            return StubCatalogue.episodes(of: season)
        }))
        await model.load()
        await model.pending?.value
        #expect(model.episodes == .failed)

        model.retryEpisodes()
        await model.pending?.value

        #expect(model.episodes == .loaded(StubCatalogue.episodes(of: Self.first)))
    }

    @Test("FR-CONTENT-03: choosing a series from search results opens its detail page")
    func seriesPickOpensDetail() {
        let home = HomeModel()
        let series = StubCatalogue.results.series[0]

        home.openSearch()
        home.open(.series(series))

        #expect(home.path == [.search, .series(series)])
    }
}
