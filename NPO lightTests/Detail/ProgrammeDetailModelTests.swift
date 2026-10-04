//
//  ProgrammeDetailModelTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

@MainActor
struct ProgrammeDetailModelTests {
    private static let film = Playable(id: EpisodeID(rawValue: "film"),
                                       title: "De wilde stad",
                                       caption: "1u 25m",
                                       synopsis: nil,
                                       duration: nil,
                                       artwork: nil)

    private let progress = ScriptedProgress()
    private let later = ScriptedWatchLater()

    private func model(_ catalogue: StubCatalogue = StubCatalogue(), in mode: Mode = .normal) -> ProgrammeDetailModel {
        ProgrammeDetailModel(summary: Self.film,
                             catalogue: catalogue,
                             watched: WatchedState(progress: progress, history: ScriptedWatchHistory(), later: later),
                             mode: mode)
    }

    private func stopped(at offset: TimeInterval?, finished: Bool = false, in mode: Mode = .normal) async {
        await progress.keep(PlaybackProgress(id: Self.film.id,
                                             offset: offset,
                                             finishedAt: finished ? Date(timeIntervalSince1970: 0) : nil,
                                             updatedAt: Date(timeIntervalSince1970: 0)),
                            in: mode)
    }

    @Test("FR-CONTENT-03: the page shows the programme as NPO describes it, and plays it as a programme of its own")
    func pageLoads() async {
        let model = model()
        #expect(model.page == .loading)
        #expect(model.request == nil)

        await model.load()

        let detail = StubCatalogue.film(Self.film.id)
        #expect(model.page == .loaded(detail))
        #expect(model.request == PlayRequest(playable: detail.playable, origin: .single))
    }

    @Test("FR-CONTENT-03: the action reads Afspelen for something unwatched and Verder kijken with a stored position")
    func actionSaysWhetherItResumes() async {
        let model = model()
        await model.load()
        #expect(!model.resumes)

        // What stopping halfway leaves, read when the player closes.
        await stopped(at: 1200)
        await model.readWatched()

        #expect(model.resumes)
        #expect(!model.isWatched)
    }

    @Test("FR-PLAY-02: a programme that was finished says so, and plays from the beginning")
    func finishedProgramme() async {
        await stopped(at: nil, finished: true)
        let model = model()

        await model.load()

        #expect(model.isWatched)
        #expect(!model.resumes)
    }

    @Test("FR-LATER-03, FR-LATER-09: the page saves the programme for later, and takes it off the list again")
    func savingToggles() async {
        let model = model()
        await model.load()
        #expect(!model.isSaved)

        await model.toggleSave()
        #expect(model.isSaved)
        // Saved as NPO describes it now.
        let described = StubCatalogue.film(Self.film.id).playable
        #expect(await later.saved(in: .normal) == [SavedItem(described, origin: .single)])

        await model.toggleSave()

        #expect(!model.isSaved)
        #expect(await later.saved(in: .normal).isEmpty)
    }

    @Test("FR-LATER-10, FR-MODE-05: what the other mode saved or watched is not this mode's")
    func otherModeIsNotShown() async {
        await later.save(SavedItem(Self.film, origin: .single), in: .kids)
        await stopped(at: 600, in: .kids)
        let model = model()

        await model.load()

        #expect(!model.isSaved)
        #expect(!model.resumes)
    }

    @Test("FR-CONTENT-06: a programme NPO says cannot be played offers no play, and can still be taken off the list")
    func unplayableOffersNoPlay() async {
        await later.save(SavedItem(Self.film, origin: .single), in: .normal)
        let unplayable = ProgrammeDetail(playable: Self.film, isPlayable: false)
        let model = model(StubCatalogue(programme: { _ in unplayable }))

        await model.load()
        #expect(model.request == nil)
        #expect(model.isSaved)

        await model.toggleSave()

        #expect(!model.isSaved)
    }

    @Test("FR-CONTENT-05: a programme NPO no longer has says so, rather than failing")
    func goneProgramme() async {
        let model = model(StubCatalogue(programme: { _ in throw BackendError.itemUnavailable }))

        await model.load()

        #expect(model.page == .unavailable)
        #expect(model.request == nil)
    }

    @Test("NFR-REL-02: a page that could not be fetched can be retried without leaving it")
    func failedPageCanBeRetried() async {
        let attempts = Counter()
        let model = model(StubCatalogue(programme: { id in
            if attempts.increment() == 1 { throw BackendError.unreachable }
            return StubCatalogue.film(id)
        }))

        await model.load()
        #expect(model.page == .failed)

        await model.load()

        #expect(model.page == .loaded(StubCatalogue.film(Self.film.id)))
    }
}
