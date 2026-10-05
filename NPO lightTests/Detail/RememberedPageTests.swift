//
//  RememberedPageTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// Pages that show what was seen before while NPO is asked again.
@MainActor
struct RememberedPageTests {
    private static let summary = StubCatalogue.results.series[0]
    private static let first = StubCatalogue.seasons[0].id
    private static let second = StubCatalogue.seasons[1].id
    private static let film = Playable(id: EpisodeID(rawValue: "film"), title: "De wilde stad", caption: nil,
                                       synopsis: nil, duration: nil, artwork: nil)

    /// The series as it was when it had one season, and one episode in it.
    private static let older = SeriesDetail(id: StubCatalogue.detail.id,
                                            title: "Freeks wilde wereld",
                                            synopsis: nil,
                                            artwork: nil,
                                            seasons: [StubCatalogue.seasons[0]])
    private static let olderEpisodes = [StubCatalogue.episodes(of: first)[0]]

    private func seriesModel(_ catalogue: RememberingCatalogue) -> SeriesDetailModel {
        SeriesDetailModel(summary: Self.summary, catalogue: catalogue, pins: ScriptedPins(), watched: .scripted(),
                          mode: .normal)
    }

    private func programmeModel(_ catalogue: RememberingCatalogue) -> ProgrammeDetailModel {
        ProgrammeDetailModel(summary: Self.film, catalogue: catalogue, watched: .scripted(), mode: .normal)
    }

    @Test("FR-CONTENT-04: a series seen before is shown at once, while NPO is still being asked")
    func rememberedSeriesIsShownAtOnce() async {
        let reached = Gate()
        let release = Gate()
        let fresh = StubCatalogue(detail: { _ in
            reached.open()
            await release.wait()
            return StubCatalogue.detail
        })
        let model = seriesModel(RememberingCatalogue(series: Self.older,
                                                     episodes: [Self.first: Self.olderEpisodes],
                                                     fresh: fresh))

        let loading = Task { await model.load() }
        await reached.wait()

        // NPO has not answered, and the page is there.
        #expect(model.page == .loaded(Self.older))
        #expect(model.pickerSeasons.isEmpty)

        release.open()
        await loading.value
        await model.pending?.value
    }

    @Test("FR-CONTENT-04: when NPO's answer differs from what was remembered, the page changes to it")
    func freshAnswerReplacesTheRemembered() async {
        let model = seriesModel(RememberingCatalogue(series: Self.older,
                                                     episodes: [Self.first: Self.olderEpisodes],
                                                     fresh: StubCatalogue()))

        await model.load()
        await model.pending?.value

        #expect(model.page == .loaded(StubCatalogue.detail))
        #expect(model.pickerSeasons == StubCatalogue.seasons)
        #expect(model.episodes == .loaded(StubCatalogue.episodes(of: Self.first)))
        // The season that was on screen stays on screen.
        #expect(model.shownSeason == Self.first)
    }

    @Test("NFR-REL-01: a series seen before stays on screen when NPO cannot be reached")
    func rememberedSeriesSurvivesAFailure() async {
        let offline = StubCatalogue(detail: { _ in throw BackendError.unreachable },
                                    season: { _ in throw BackendError.unreachable })
        let model = seriesModel(RememberingCatalogue(series: Self.older,
                                                     episodes: [Self.first: Self.olderEpisodes],
                                                     fresh: offline))

        await model.load()
        await model.pending?.value

        #expect(model.page == .loaded(Self.older))
        #expect(model.episodes == .loaded(Self.olderEpisodes))
    }

    @Test("NFR-REL-02: a season never seen before still fails with a retry when NPO cannot be reached")
    func unseenSeasonStillFails() async {
        let offline = StubCatalogue(season: { _ in throw BackendError.unreachable })
        let model = seriesModel(RememberingCatalogue(series: StubCatalogue.detail, fresh: offline))

        await model.load()
        await model.pending?.value

        #expect(model.page == .loaded(StubCatalogue.detail))
        #expect(model.episodes == .failed)
    }

    @Test("FR-CONTENT-05: a remembered series NPO no longer has says so, rather than showing what it was")
    func rememberedSeriesThatIsGone() async {
        let gone = StubCatalogue(detail: { _ in throw BackendError.itemUnavailable })
        let model = seriesModel(RememberingCatalogue(series: Self.older, fresh: gone))

        await model.load()

        #expect(model.page == .unavailable)
    }

    @Test("FR-CONTENT-04: a programme seen before is shown at once, and updated when NPO describes it otherwise")
    func rememberedProgramme() async {
        let remembered = ProgrammeDetail(playable: Self.film, isPlayable: true)
        let reached = Gate()
        let release = Gate()
        let fresh = StubCatalogue(programme: { id in
            reached.open()
            await release.wait()
            return StubCatalogue.film(id)
        })
        let model = programmeModel(RememberingCatalogue(programme: remembered, fresh: fresh))

        let loading = Task { await model.load() }
        await reached.wait()
        #expect(model.page == .loaded(remembered))
        #expect(model.request?.playable == Self.film)

        release.open()
        await loading.value

        #expect(model.page == .loaded(StubCatalogue.film(Self.film.id)))
    }

    @Test("NFR-REL-01: a programme seen before stays on screen when NPO cannot be reached")
    func rememberedProgrammeSurvivesAFailure() async {
        let remembered = ProgrammeDetail(playable: Self.film, isPlayable: true)
        let offline = StubCatalogue(programme: { _ in throw BackendError.unreachable })
        let model = programmeModel(RememberingCatalogue(programme: remembered, fresh: offline))

        await model.load()

        #expect(model.page == .loaded(remembered))
    }
}
