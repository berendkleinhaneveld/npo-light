//
//  SharedPositionsTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// NPO's positions, taken into the television's own store.
@MainActor
struct SharedPositionsTests {
    nonisolated private static let episode = EpisodeID(rawValue: "episode-1")
    nonisolated private static let hour: TimeInterval = 3600
    nonisolated private static let now = Date(timeIntervalSince1970: 1_000_000)

    private let store = ScriptedProgress()
    private let clock = TestClock(now: SharedPositionsTests.now)

    private var positions: SharedPositions {
        SharedPositions(progress: store, clock: clock)
    }

    private var coordinator: PlaybackCoordinator {
        PlaybackCoordinator(watched: WatchedState(progress: store,
                                                  history: ScriptedWatchHistory(),
                                                  later: ScriptedWatchLater()),
                            order: EpisodeOrder(catalogue: StubCatalogue()),
                            clock: clock)
    }

    nonisolated private static func position(_ offset: TimeInterval,
                                             of duration: TimeInterval? = hour) -> SharedPosition {
        SharedPosition(offset: offset, duration: duration)
    }

    @Test("FR-PLAY-13: something watched on another device resumes where NPO says it was left")
    func npoPositionIsWhereItResumes() async {
        let news = await positions.take([Self.episode: Self.position(900)], in: .normal)

        #expect(news == [Self.episode])
        #expect(await coordinator.resumePoint(of: Self.episode, in: .normal) == 900)
        #expect(await store.progress(of: Self.episode, in: .normal)?.duration == Self.hour)
    }

    @Test("FR-PLAY-13: a position NPO has replaces the television's own when it is news")
    func newsReplacesTheTelevisionsOwn() async {
        let coordinator = coordinator
        await coordinator.played(Self.episode, to: 300, of: Self.hour, in: .normal, resting: true)

        await positions.take([Self.episode: Self.position(1200)], in: .normal)

        #expect(await coordinator.resumePoint(of: Self.episode, in: .normal) == 1200)
    }

    @Test("FR-PLAY-13: NPO repeating a position does not undo what the television wrote since")
    func repeatedPositionChangesNothing() async {
        let coordinator = coordinator
        await positions.take([Self.episode: Self.position(300)], in: .normal)
        // Played on here, and the report of it never reached NPO.
        await coordinator.played(Self.episode, to: 1500, of: Self.hour, in: .normal, resting: true)

        let news = await positions.take([Self.episode: Self.position(300)], in: .normal)

        #expect(news.isEmpty)
        #expect(await coordinator.resumePoint(of: Self.episode, in: .normal) == 1500)
    }

    @Test("FR-PLAY-13: a position NPO rounds on one page and not on another is the same position")
    func roundedPositionIsNotNews() async {
        await positions.take([Self.episode: Self.position(88.965560839)], in: .normal)

        #expect(await positions.take([Self.episode: Self.position(89)], in: .normal).isEmpty)
        #expect(await positions.isKnown(Self.position(89), of: Self.episode, in: .normal))
        #expect(await !positions.isKnown(Self.position(95), of: Self.episode, in: .normal))
    }

    @Test("FR-PLAY-13, FR-PLAY-04: a position past the completion threshold marks the item finished")
    func positionPastTheThresholdFinishes() async {
        await positions.take([Self.episode: Self.position(3590)], in: .normal)

        let progress = await store.progress(of: Self.episode, in: .normal)
        #expect(progress?.finishedAt == Self.now)
        #expect(progress?.offset == nil)
        #expect(await coordinator.resumePoint(of: Self.episode, in: .normal) == nil)
    }

    @Test("FR-PLAY-13: a position before the threshold never makes a finished item unfinished")
    func finishedStaysFinished() async {
        let coordinator = coordinator
        await coordinator.playedToEnd(Self.episode, in: .normal)
        clock.advance(by: .seconds(60))

        await positions.take([Self.episode: Self.position(120)], in: .normal)

        let progress = await store.progress(of: Self.episode, in: .normal)
        #expect(progress?.finishedAt == Self.now)
        #expect(progress?.offset == 120)
    }

    @Test("FR-PLAY-13, FR-MODE-05: a position is taken over into the mode whose profile it belongs to")
    func positionStaysInItsMode() async {
        await positions.take([Self.episode: Self.position(900)], in: .kids)

        #expect(await coordinator.resumePoint(of: Self.episode, in: .kids) == 900)
        #expect(await coordinator.resumePoint(of: Self.episode, in: .normal) == nil)
    }

    @Test("FR-PLAY-13: what NPO said is kept through everything the television writes after it")
    func whatNPOSaidOutlivesLocalWrites() async {
        let coordinator = coordinator
        await positions.take([Self.episode: Self.position(300)], in: .normal)

        await coordinator.played(Self.episode, to: 400, of: Self.hour, in: .normal, resting: false)
        await coordinator.playedToEnd(Self.episode, in: .normal)

        #expect(await store.progress(of: Self.episode, in: .normal)?.shared == 300)
    }

    @Test("FR-PLAY-13: playing something NPO has a position for takes that position over first")
    func noticedPositionIsTakenOver() async {
        let coordinator = coordinator

        await coordinator.noticed(Self.position(777), of: Self.episode, in: .normal)
        await coordinator.noticed(nil, of: Self.episode, in: .normal)

        #expect(await coordinator.resumePoint(of: Self.episode, in: .normal) == 777)
    }

    // MARK: on the way up from the catalogue

    nonisolated private static func episode(_ name: String, at offset: TimeInterval?) -> Playable {
        Playable(id: EpisodeID(rawValue: name), title: name, caption: nil, synopsis: nil, duration: nil,
                 artwork: nil, position: offset.map { SharedPosition(offset: $0, duration: hour) })
    }

    @Test("FR-PLAY-13: a list of episodes brings the positions NPO sent with it into the store")
    func seasonListBringsItsPositions() async throws {
        let listed = [Self.episode("one", at: 3590), Self.episode("two", at: 600), Self.episode("three", at: nil)]
        let catalogue = PositionTakingCatalogue(wrapping: StubCatalogue(season: { _ in listed }), positions: positions)

        let episodes = try await catalogue.episodes(of: SeasonID(rawValue: "season-1"), in: .normal)

        #expect(episodes == listed)
        let known = await store.progress(of: listed.map(\.id), in: .normal)
        #expect(known[listed[0].id]?.isFinished == true)
        #expect(known[listed[1].id]?.offset == 600)
        #expect(known[listed[2].id] == nil)
    }

    @Test("FR-PLAY-13: a programme's page and a search bring their positions too")
    func pageAndSearchBringPositions() async throws {
        let film = Self.episode("film", at: 1800)
        let found = Self.episode("found", at: 45)
        let stub = StubCatalogue(
            answer: { _ in SearchResults(series: [], singleProgrammes: [], episodes: [found]) },
            programme: { _ in ProgrammeDetail(playable: film, isPlayable: true) }
        )
        let catalogue = PositionTakingCatalogue(wrapping: stub, positions: positions)

        _ = try await catalogue.programme(film.id, in: .normal)
        _ = try await catalogue.search(for: "f", in: .normal)

        #expect(await store.progress(of: film.id, in: .normal)?.offset == 1800)
        #expect(await store.progress(of: found.id, in: .normal)?.offset == 45)
    }

    @Test("FR-CONTENT-04: what a catalogue remembers is still there to show at once, under the positions")
    func rememberedAnswersPassThrough() async {
        let remembered = [Self.episode("one", at: nil)]
        let season = SeasonID(rawValue: "season-1")
        let inner = RememberingCatalogue(series: StubCatalogue.detail,
                                         episodes: [season: remembered],
                                         programme: StubCatalogue.film(EpisodeID(rawValue: "film")),
                                         fresh: StubCatalogue())
        let catalogue = PositionTakingCatalogue(wrapping: inner, positions: positions)

        #expect(await catalogue.rememberedEpisodes(of: season, in: .normal) == remembered)
        #expect(await catalogue.rememberedSeries(StubCatalogue.detail.id, in: .normal) == StubCatalogue.detail)
        #expect(await catalogue.rememberedProgramme(EpisodeID(rawValue: "film"), in: .normal) != nil)
    }
}
