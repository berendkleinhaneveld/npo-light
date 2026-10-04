//
//  WatchedThreadTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// Which episode a series continues with, as playback moves through it.
@MainActor
struct WatchedThreadTests {
    private static let hour: TimeInterval = 3600
    private static let series = StubCatalogue.results.series[0]
    private static let first = StubCatalogue.seasons[0].id
    private static let second = StubCatalogue.seasons[1].id

    private let history = ScriptedWatchHistory()
    private let clock = TestClock(now: Date(timeIntervalSince1970: 1_000_000))

    private func coordinator(_ catalogue: StubCatalogue = StubCatalogue()) -> PlaybackCoordinator {
        PlaybackCoordinator(progress: ScriptedProgress(),
                            history: history,
                            order: EpisodeOrder(catalogue: catalogue),
                            clock: clock)
    }

    private static func place(in season: SeasonID) -> SeriesPlace {
        SeriesPlace(series: series, season: season)
    }

    private static func episode(_ number: Int, of season: SeasonID) -> Playable {
        StubCatalogue.episodes(of: season)[number - 1]
    }

    private var entry: WatchedEntry? {
        get async { await history.entry(for: Self.series.id, in: .normal) }
    }

    @Test("FR-PLAY-09: starting an episode makes its series the most recently watched, continuing with it")
    func startingRecordsTheSeries() async {
        let episode = Self.episode(1, of: Self.first)

        await coordinator().started(episode, from: .series(Self.place(in: Self.first)), in: .normal)

        #expect(await entry == WatchedEntry(series: Self.series,
                                            next: Upcoming(episode, in: Self.first),
                                            playedAt: clock.now))
    }

    @Test("FR-PLAY-09, FR-MODE-05: what is recorded is recorded for the mode it was played in")
    func recordedPerMode() async {
        let place = Self.place(in: Self.first)

        await coordinator().started(Self.episode(1, of: Self.first), from: .series(place), in: .kids)

        #expect(await entry == nil)
        #expect(await history.entry(for: Self.series.id, in: .kids) != nil)
    }

    @Test("FR-PLAY-09: a series is one entry, whichever of its episodes is played")
    func oneEntryForASeries() async {
        let coordinator = coordinator()

        let early = PlayOrigin.series(Self.place(in: Self.first))
        let late = PlayOrigin.series(Self.place(in: Self.second))

        await coordinator.started(Self.episode(1, of: Self.first), from: early, in: .normal)
        await coordinator.started(Self.episode(2, of: Self.second), from: late, in: .normal)

        #expect(await history.entries(in: .normal).count == 1)
        #expect(await entry?.next?.id == Self.episode(2, of: Self.second).id)
    }

    @Test("FR-PLAY-09: something whose series is not known records no series")
    func withoutAPlaceNothingIsRecorded() async {
        let coordinator = coordinator()
        let episode = Self.episode(1, of: Self.first)

        await coordinator.started(episode, from: .unknown, in: .normal)
        await coordinator.played(episode.id, to: 3550, of: Self.hour, in: .normal, resting: true)

        #expect(await history.entries(in: .normal).isEmpty)
    }

    @Test("FR-PLAY-09, FR-HOME-07: finishing an episode leaves the series pointing at the next one")
    func finishingMovesOn() async {
        let coordinator = coordinator()
        let episode = Self.episode(1, of: Self.first)
        let place = Self.place(in: Self.first)
        await coordinator.started(episode, from: .series(place), in: .normal)

        await coordinator.played(episode.id, from: .series(place), to: 1800, of: Self.hour, in: .normal, resting: false)
        #expect(await entry?.next?.id == episode.id)

        await coordinator.played(episode.id, from: .series(place), to: 3510, of: Self.hour, in: .normal, resting: false)

        #expect(await entry?.next == Upcoming(Self.episode(2, of: Self.first), in: Self.first))
        #expect(await entry?.finishedAt == nil)
    }

    @Test("FR-HOME-04: the last episode of a season moves the series on to the next season")
    func finishingASeasonMovesOn() async {
        let coordinator = coordinator()
        let episode = Self.episode(2, of: Self.first)
        let place = Self.place(in: Self.first)
        await coordinator.started(episode, from: .series(place), in: .normal)

        await coordinator.playedToEnd(episode.id, from: .series(place), in: .normal)

        #expect(await entry?.next == Upcoming(Self.episode(1, of: Self.second), in: Self.second))
    }

    @Test("FR-HOME-07: finishing the last episode leaves nothing to watch, from that moment")
    func finishingTheSeries() async {
        let coordinator = coordinator()
        let episode = Self.episode(2, of: Self.second)
        let place = Self.place(in: Self.second)
        await coordinator.started(episode, from: .series(place), in: .normal)
        clock.advance(by: .seconds(Self.hour))

        await coordinator.played(episode.id, from: .series(place), to: 3550, of: Self.hour, in: .normal, resting: true)

        #expect(await entry?.next == nil)
        #expect(await entry?.finishedAt == clock.now)
    }

    @Test("FR-PLAY-09: the credits running on do not move the series on a second time")
    func movesOnOnce() async {
        let catalogue = StubCatalogue()
        let coordinator = coordinator(catalogue)
        let episode = Self.episode(1, of: Self.first)
        let place = Self.place(in: Self.first)
        await coordinator.started(episode, from: .series(place), in: .normal)

        await coordinator.played(episode.id, from: .series(place), to: 3510, of: Self.hour, in: .normal, resting: false)
        await coordinator.played(episode.id, from: .series(place), to: 3520, of: Self.hour, in: .normal, resting: false)
        await coordinator.playedToEnd(episode.id, from: .series(place), in: .normal)

        #expect(await entry?.next?.id == Self.episode(2, of: Self.first).id)
        #expect(catalogue.seasonRequests == [Self.first])
    }

    @Test("FR-HOME-07: playing a finished series again makes it a live entry")
    func playingAgainIsLive() async {
        let coordinator = coordinator()
        let last = Self.episode(2, of: Self.second)
        await coordinator.started(last, from: .series(Self.place(in: Self.second)), in: .normal)
        await coordinator.playedToEnd(last.id, from: .series(Self.place(in: Self.second)), in: .normal)

        let again = Self.episode(1, of: Self.first)
        await coordinator.started(again, from: .series(Self.place(in: Self.first)), in: .normal)

        #expect(await entry?.next?.id == again.id)
        #expect(await entry?.finishedAt == nil)
    }

    @Test("NFR-REL-02: when NPO cannot say what follows, the series stays where it was and is not called finished")
    func unknownFollowerStays() async {
        let coordinator = coordinator(StubCatalogue(season: { _ in throw BackendError.unreachable }))
        let episode = Self.episode(1, of: Self.first)
        let place = Self.place(in: Self.first)
        await coordinator.started(episode, from: .series(place), in: .normal)

        await coordinator.playedToEnd(episode.id, from: .series(place), in: .normal)

        #expect(await entry?.next?.id == episode.id)
        #expect(await entry?.finishedAt == nil)
    }

    // MARK: What plays next

    @Test("FR-PLAY-05, FR-PLAY-07: an episode that reaches its end is followed by the next, also across seasons")
    func endAnswersTheNextEpisode() async {
        let coordinator = coordinator()
        let episode = Self.episode(2, of: Self.first)
        let place = Self.place(in: Self.first)
        await coordinator.started(episode, from: .series(place), in: .normal)

        let next = await coordinator.playedToEnd(episode.id, from: .series(place), in: .normal)

        #expect(next?.playable.id == Self.episode(1, of: Self.second).id)
        #expect(next?.origin == .series(Self.place(in: Self.second)))
    }

    @Test("FR-PLAY-07: nothing follows the last episode, a single programme, or an episode whose follower is not known")
    func endAnswersNothing() async {
        let last = Self.episode(2, of: Self.second)
        let coordinator = coordinator()
        await coordinator.started(last, from: .series(Self.place(in: Self.second)), in: .normal)
        await coordinator.started(Self.film, from: .single, in: .normal)
        let unreachable = self.coordinator(StubCatalogue(season: { _ in throw BackendError.unreachable }))

        #expect(await coordinator.playedToEnd(last.id, from: .series(Self.place(in: Self.second)), in: .normal) == nil)
        #expect(await coordinator.playedToEnd(Self.film.id, from: .single, in: .normal) == nil)
        #expect(await coordinator.playedToEnd(last.id, from: .unknown, in: .normal) == nil)

        let first = Self.episode(1, of: Self.first)
        await unreachable.started(first, from: .series(Self.place(in: Self.first)), in: .normal)
        #expect(await unreachable.playedToEnd(first.id, from: .series(Self.place(in: Self.first)), in: .normal) == nil)
    }

    // MARK: A single programme

    private static let film = Playable(id: EpisodeID(rawValue: "film"),
                                       title: "De wilde stad",
                                       caption: "1u 25m",
                                       synopsis: nil,
                                       duration: nil,
                                       artwork: nil)

    private var filmEntry: WatchedEntry? {
        get async { await history.entry(for: ItemID(rawValue: "film"), in: .normal) }
    }

    @Test("FR-PLAY-09: starting a single programme records it as an item of its own")
    func singleProgrammeIsRecorded() async {
        await coordinator().started(Self.film, from: .single, in: .normal)

        #expect(await filmEntry == WatchedEntry(single: Self.film, playedAt: clock.now))
        #expect(await filmEntry?.kind == .single)
        #expect(await filmEntry?.next?.id == Self.film.id)
    }

    @Test("FR-HOME-07: finishing a single programme leaves nothing to watch, without asking NPO what follows")
    func finishingASingleProgramme() async {
        let catalogue = StubCatalogue()
        let coordinator = coordinator(catalogue)
        await coordinator.started(Self.film, from: .single, in: .normal)

        await coordinator.played(Self.film.id, from: .single, to: 5090, of: 5100, in: .normal, resting: true)

        #expect(await filmEntry?.next == nil)
        #expect(await filmEntry?.finishedAt == clock.now)
        #expect(catalogue.seasonRequests.isEmpty)
    }

    @Test("FR-HOME-08: an item taken off the row comes back when it is played again")
    func playingAgainUnhides() async throws {
        let coordinator = coordinator()
        await coordinator.started(Self.film, from: .single, in: .normal)
        await history.hide(ItemID(rawValue: "film"), in: .normal)
        #expect(await filmEntry?.isHidden == true)

        await coordinator.started(Self.film, from: .single, in: .normal)

        #expect(await filmEntry?.isHidden == false)
    }

    @Test("FR-HOME-08: an episode finishing does not bring back a series that was taken off the row")
    func finishingKeepsItHidden() async {
        let coordinator = coordinator()
        let episode = Self.episode(1, of: Self.first)
        let place = Self.place(in: Self.first)
        await coordinator.started(episode, from: .series(place), in: .normal)
        await history.hide(Self.series.id, in: .normal)

        await coordinator.playedToEnd(episode.id, from: .series(place), in: .normal)

        #expect(await entry?.next?.id == Self.episode(2, of: Self.first).id)
        #expect(await entry?.isHidden == true)
    }
}
