//
//  AskedAgainTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// Pages that are asked to load again while they are showing: what happens
/// when the television wakes on them.
@MainActor
struct AskedAgainTests {
    nonisolated private static let series = StubCatalogue.results.series[0]
    nonisolated private static let first = StubCatalogue.seasons[0].id
    nonisolated private static let second = StubCatalogue.seasons[1].id
    nonisolated private static let start = Date(timeIntervalSince1970: 0)
    nonisolated private static let film = named("film", "De wilde stad")
    nonisolated private static let added = named("added", "Nieuw")

    nonisolated private static func named(_ id: String, _ title: String) -> Playable {
        Playable(id: EpisodeID(rawValue: id), title: title, caption: nil, synopsis: nil, duration: nil, artwork: nil)
    }

    private let progress = ScriptedProgress()
    private let history = ScriptedWatchHistory()

    private func model(_ catalogue: StubCatalogue) -> SeriesDetailModel {
        SeriesDetailModel(summary: Self.series,
                          catalogue: catalogue,
                          pins: ScriptedPins(),
                          watched: WatchedState(progress: progress, history: history, later: ScriptedWatchLater()),
                          mode: .normal)
    }

    /// A catalogue whose seasons gain an episode once `grown` is set.
    private func growing(_ grown: Flag) -> StubCatalogue {
        StubCatalogue(season: { [grown] season in
            StubCatalogue.episodes(of: season) + (grown.isSet ? [Self.added] : [])
        })
    }

    @Test("FR-CONTENT-09: a series' page that is asked again shows the episode added to the season it shows")
    func addedEpisodeIsListed() async {
        let grown = Flag()
        let model = model(growing(grown))
        await model.load()
        await model.pending?.value
        model.show(Self.second)
        await model.pending?.value

        grown.set()
        await model.load()
        await model.pending?.value

        #expect(model.shownSeason == Self.second)
        #expect(model.episodes == .loaded(StubCatalogue.episodes(of: Self.second) + [Self.added]))
    }

    @Test("FR-CONTENT-09: a season seen before the page was asked again is asked for again when it is shown")
    func otherSeasonsAreAskedForAgain() async {
        let grown = Flag()
        let model = model(growing(grown))
        await model.load()
        await model.pending?.value
        model.show(Self.second)
        await model.pending?.value

        grown.set()
        await model.load()
        await model.pending?.value
        model.show(Self.first)
        await model.pending?.value

        #expect(model.episodes == .loaded(StubCatalogue.episodes(of: Self.first) + [Self.added]))
    }

    @Test("FR-CONTENT-09: a series' page stays on screen while it is asked again")
    func pageStaysWhileAskedAgain() async {
        let holds = Flag()
        let reached = Gate()
        let release = Gate()
        let model = model(StubCatalogue(detail: { [holds] _ in
            if holds.isSet {
                reached.open()
                await release.wait()
            }
            return StubCatalogue.detail
        }))
        await model.load()
        await model.pending?.value

        holds.set()
        let again = Task { await model.load() }
        await reached.wait()

        #expect(model.page == .loaded(StubCatalogue.detail))
        #expect(model.episodes == .loaded(StubCatalogue.episodes(of: Self.first)))

        release.open()
        await again.value
        await model.pending?.value
    }

    @Test("FR-CONTENT-09, NFR-REL-01: a series' page keeps what it shows when asking again fails")
    func failureLeavesThePage() async {
        let fails = Flag()
        let model = model(StubCatalogue(detail: { [fails] _ in
            if fails.isSet { throw BackendError.unreachable }
            return StubCatalogue.detail
        }, season: { [fails] season in
            if fails.isSet { throw BackendError.unreachable }
            return StubCatalogue.episodes(of: season)
        }))
        await model.load()
        await model.pending?.value

        fails.set()
        await model.load()
        await model.pending?.value

        #expect(model.page == .loaded(StubCatalogue.detail))
        #expect(model.episodes == .loaded(StubCatalogue.episodes(of: Self.first)))
    }

    @Test("FR-CONTENT-09, FR-HOME-14: a series watched to its end offers the episode added while its page was showing")
    func mainActionOffersTheAddedEpisode() async {
        for episode in StubCatalogue.episodes(of: Self.first) + StubCatalogue.episodes(of: Self.second) {
            await progress.keep(PlaybackProgress(id: episode.id, offset: nil, finishedAt: Self.start,
                                                 updatedAt: Self.start),
                                in: .normal)
        }
        var entry = WatchedEntry(series: Self.series, next: nil, playedAt: Self.start)
        entry.finishedAt = Self.start
        await history.record(entry, in: .normal)
        let grown = Flag()
        let model = model(growing(grown))
        await model.load()
        await model.pending?.value
        #expect(model.isFullyWatched)

        grown.set()
        await model.load()
        await model.pending?.value

        #expect(model.primary == .init(episode: Self.added, season: Self.second, resumes: false))
        #expect(!model.isFullyWatched)
    }

    @Test("FR-CONTENT-09: a programme's page stays on screen while it is asked again, and takes the new answer")
    func programmeIsAskedAgain() async {
        let changed = Flag()
        let reached = Gate()
        let release = Gate()
        let gone = ProgrammeDetail(playable: StubCatalogue.film(Self.film.id).playable, isPlayable: false)
        let catalogue = StubCatalogue(programme: { [changed] id in
            guard changed.isSet else { return StubCatalogue.film(id) }
            reached.open()
            await release.wait()
            return gone
        })
        let model = ProgrammeDetailModel(summary: Self.film, catalogue: catalogue, watched: .scripted(),
                                         mode: .normal)
        await model.load()

        changed.set()
        let again = Task { await model.load() }
        await reached.wait()
        #expect(model.page == .loaded(StubCatalogue.film(Self.film.id)))

        release.open()
        await again.value
        #expect(model.page == .loaded(gone))
    }
}
