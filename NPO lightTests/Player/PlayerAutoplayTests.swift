//
//  PlayerAutoplayTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// What the player does when what it plays reaches its end.
@MainActor
struct PlayerAutoplayTests {
    private static let series = StubCatalogue.results.series[0]
    private static let first = StubCatalogue.seasons[0].id
    private static let second = StubCatalogue.seasons[1].id

    private let playback = StubPlayback()
    private let clock = TestClock()

    private static func episode(_ number: Int, of season: SeasonID) -> Playable {
        StubCatalogue.episodes(of: season)[number - 1]
    }

    private func model(playing playable: Playable,
                       from origin: PlayOrigin,
                       in mode: Mode = .normal,
                       starter: StubPlayback? = nil) -> PlayerModel {
        PlayerModel(playable: playable,
                    origin: origin,
                    mode: mode,
                    starter: starter ?? playback,
                    positions: PlaybackCoordinator(watched: .scripted(),
                                                   order: EpisodeOrder(catalogue: StubCatalogue()),
                                                   clock: clock),
                    clock: clock)
    }

    private static func place(in season: SeasonID) -> PlayOrigin {
        .series(SeriesPlace(series: series, season: season))
    }

    @Test("FR-PLAY-05: when an episode ends the next one starts without anything being pressed")
    func nextEpisodeStartsByItself() async {
        let model = model(playing: Self.episode(1, of: Self.first), from: Self.place(in: Self.first))
        await model.start()

        await model.ended()

        #expect(model.playable.id == Self.episode(2, of: Self.first).id)
        #expect(playback.requests.map(\.playable.id) == [Self.episode(1, of: Self.first).id,
                                                         Self.episode(2, of: Self.first).id])
        #expect(!model.isOver)
        #expect(model.problem == nil)
    }

    @Test("FR-PLAY-05: the player names the episode that started by itself, for a while")
    func nextEpisodeIsAnnounced() async {
        let model = model(playing: Self.episode(1, of: Self.first), from: Self.place(in: Self.first))
        await model.start()
        #expect(model.announced == nil)

        await model.ended()
        #expect(model.announced?.id == Self.episode(2, of: Self.first).id)

        await model.announcing?.value

        #expect(model.announced == nil)
        #expect(clock.waits == [PlayerModel.announcementTime])
        #expect(PlayerModel.announcementTime >= .seconds(5))
    }

    @Test("FR-PLAY-05: choosing to stop ends the sitting, back to where playback was started from")
    func stoppingEndsTheSitting() async {
        let model = model(playing: Self.episode(1, of: Self.first), from: Self.place(in: Self.first))
        await model.start()
        await model.ended()

        model.stopGoingOn()

        #expect(model.isOver)
    }

    @Test("FR-PLAY-07: the end of a season goes on into the next season, and says which it is in")
    func goesOnAcrossSeasons() async {
        let model = model(playing: Self.episode(2, of: Self.first), from: Self.place(in: Self.first))
        await model.start()

        await model.ended()

        #expect(model.playable.id == Self.episode(1, of: Self.second).id)
        #expect(model.origin == Self.place(in: Self.second))
    }

    @Test("FR-PLAY-07: the last episode of a series ends the sitting")
    func lastEpisodeEndsTheSitting() async {
        let model = model(playing: Self.episode(2, of: Self.second), from: Self.place(in: Self.second))
        await model.start()

        await model.ended()

        #expect(model.isOver)
        #expect(model.announced == nil)
        #expect(playback.requests.count == 1)
    }

    @Test("FR-PLAY-07: a single programme never goes on into anything", arguments: [PlayOrigin.single, .unknown])
    func nothingFollowsWhatStandsAlone(origin: PlayOrigin) async {
        let model = model(playing: Self.episode(1, of: Self.first), from: origin)
        await model.start()

        await model.ended()

        #expect(model.isOver)
        #expect(playback.requests.count == 1)
    }

    @Test("FR-PLAY-06: kids mode does not go on by itself until it can pause first")
    func kidsModeDoesNotGoOn() async {
        let model = model(playing: Self.episode(1, of: Self.first), from: Self.place(in: Self.first), in: .kids)
        await model.start()

        await model.ended()

        #expect(model.isOver)
        #expect(playback.requests.count == 1)
    }

    @Test("FR-PLAY-10: a next episode that will not start is a problem with a retry, and is not announced")
    func nextEpisodeThatFails() async {
        var attempts = 0
        let failing = StubPlayback { _, _ in
            attempts += 1
            if attempts == 2 { throw BackendError.unreachable }
        }
        let model = model(playing: Self.episode(1, of: Self.first), from: Self.place(in: Self.first), starter: failing)
        await model.start()

        await model.ended()
        #expect(model.problem == .unreachable)
        #expect(model.announced == nil)

        // The retry is for the next episode, not the one that ended.
        await model.start()

        #expect(failing.requests.last?.playable.id == Self.episode(2, of: Self.first).id)
        #expect(model.problem == nil)
    }

    @Test("FR-PLAY-05: a player that was closed as its episode ended starts nothing")
    func closedPlayerDoesNotGoOn() async {
        let model = model(playing: Self.episode(1, of: Self.first), from: Self.place(in: Self.first))
        await model.start()
        model.stop()

        await model.ended()

        #expect(playback.requests.count == 1)
        #expect(model.announced == nil)
    }
}
