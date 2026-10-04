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
        SeriesPlace(series: series, seasons: [first, second], season: season)
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

        await coordinator().started(episode, at: Self.place(in: Self.first), in: .normal)

        #expect(await entry == WatchedEntry(series: Self.series,
                                            next: Upcoming(episode, in: Self.first),
                                            playedAt: clock.now))
    }

    @Test("FR-PLAY-09, FR-MODE-05: what is recorded is recorded for the mode it was played in")
    func recordedPerMode() async {
        await coordinator().started(Self.episode(1, of: Self.first), at: Self.place(in: Self.first), in: .kids)

        #expect(await entry == nil)
        #expect(await history.entry(for: Self.series.id, in: .kids) != nil)
    }

    @Test("FR-PLAY-09: a series is one entry, whichever of its episodes is played")
    func oneEntryForASeries() async {
        let coordinator = coordinator()

        await coordinator.started(Self.episode(1, of: Self.first), at: Self.place(in: Self.first), in: .normal)
        await coordinator.started(Self.episode(2, of: Self.second), at: Self.place(in: Self.second), in: .normal)

        #expect(await history.entries(in: .normal).count == 1)
        #expect(await entry?.next?.id == Self.episode(2, of: Self.second).id)
    }

    @Test("FR-PLAY-09: something whose series is not known records no series")
    func withoutAPlaceNothingIsRecorded() async {
        let coordinator = coordinator()
        let episode = Self.episode(1, of: Self.first)

        await coordinator.started(episode, at: nil, in: .normal)
        await coordinator.played(episode.id, to: 3550, of: Self.hour, in: .normal, resting: true)

        #expect(await history.entries(in: .normal).isEmpty)
    }

    @Test("FR-PLAY-09, FR-HOME-07: finishing an episode leaves the series pointing at the next one")
    func finishingMovesOn() async {
        let coordinator = coordinator()
        let episode = Self.episode(1, of: Self.first)
        let place = Self.place(in: Self.first)
        await coordinator.started(episode, at: place, in: .normal)

        await coordinator.played(episode.id, at: place, to: 1800, of: Self.hour, in: .normal, resting: false)
        #expect(await entry?.next?.id == episode.id)

        await coordinator.played(episode.id, at: place, to: 3510, of: Self.hour, in: .normal, resting: false)

        #expect(await entry?.next == Upcoming(Self.episode(2, of: Self.first), in: Self.first))
        #expect(await entry?.finishedAt == nil)
    }

    @Test("FR-HOME-04: the last episode of a season moves the series on to the next season")
    func finishingASeasonMovesOn() async {
        let coordinator = coordinator()
        let episode = Self.episode(2, of: Self.first)
        let place = Self.place(in: Self.first)
        await coordinator.started(episode, at: place, in: .normal)

        await coordinator.playedToEnd(episode.id, at: place, in: .normal)

        #expect(await entry?.next == Upcoming(Self.episode(1, of: Self.second), in: Self.second))
    }

    @Test("FR-HOME-07: finishing the last episode leaves nothing to watch, from that moment")
    func finishingTheSeries() async {
        let coordinator = coordinator()
        let episode = Self.episode(2, of: Self.second)
        let place = Self.place(in: Self.second)
        await coordinator.started(episode, at: place, in: .normal)
        clock.advance(by: .seconds(Self.hour))

        await coordinator.played(episode.id, at: place, to: 3550, of: Self.hour, in: .normal, resting: true)

        #expect(await entry?.next == nil)
        #expect(await entry?.finishedAt == clock.now)
    }

    @Test("FR-PLAY-09: the credits running on do not move the series on a second time")
    func movesOnOnce() async {
        let catalogue = StubCatalogue()
        let coordinator = coordinator(catalogue)
        let episode = Self.episode(1, of: Self.first)
        let place = Self.place(in: Self.first)
        await coordinator.started(episode, at: place, in: .normal)

        await coordinator.played(episode.id, at: place, to: 3510, of: Self.hour, in: .normal, resting: false)
        await coordinator.played(episode.id, at: place, to: 3520, of: Self.hour, in: .normal, resting: false)
        await coordinator.playedToEnd(episode.id, at: place, in: .normal)

        #expect(await entry?.next?.id == Self.episode(2, of: Self.first).id)
        #expect(catalogue.seasonRequests == [Self.first])
    }

    @Test("FR-HOME-07: playing a finished series again makes it a live entry")
    func playingAgainIsLive() async {
        let coordinator = coordinator()
        let last = Self.episode(2, of: Self.second)
        await coordinator.started(last, at: Self.place(in: Self.second), in: .normal)
        await coordinator.playedToEnd(last.id, at: Self.place(in: Self.second), in: .normal)

        let again = Self.episode(1, of: Self.first)
        await coordinator.started(again, at: Self.place(in: Self.first), in: .normal)

        #expect(await entry?.next?.id == again.id)
        #expect(await entry?.finishedAt == nil)
    }

    @Test("NFR-REL-02: when NPO cannot say what follows, the series stays where it was and is not called finished")
    func unknownFollowerStays() async {
        let coordinator = coordinator(StubCatalogue(season: { _ in throw BackendError.unreachable }))
        let episode = Self.episode(1, of: Self.first)
        let place = Self.place(in: Self.first)
        await coordinator.started(episode, at: place, in: .normal)

        await coordinator.playedToEnd(episode.id, at: place, in: .normal)

        #expect(await entry?.next?.id == episode.id)
        #expect(await entry?.finishedAt == nil)
    }
}
