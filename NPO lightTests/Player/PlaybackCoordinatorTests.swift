//
//  PlaybackCoordinatorTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

@MainActor
struct PlaybackCoordinatorTests {
    private static let episode = EpisodeID(rawValue: "episode-1")
    private static let hour: TimeInterval = 3600

    private let store = ScriptedProgress()
    private let later = ScriptedWatchLater()
    private let clock = TestClock(now: Date(timeIntervalSince1970: 1_000_000))

    private var coordinator: PlaybackCoordinator {
        PlaybackCoordinator(watched: WatchedState(progress: store,
                                                  history: ScriptedWatchHistory(),
                                                  later: later),
                            order: EpisodeOrder(catalogue: StubCatalogue()),
                            clock: clock)
    }

    @Test("FR-PLAY-02: something never played starts at the beginning")
    func nothingStoredStartsAtTheBeginning() async {
        #expect(await coordinator.resumePoint(of: Self.episode, in: .normal) == nil)
    }

    @Test("FR-PLAY-02: stopping halfway and playing again resumes where playback stopped")
    func resumesWhereItStopped() async {
        let coordinator = coordinator

        await coordinator.played(Self.episode, to: 1234.5, of: Self.hour, in: .normal, resting: true)

        #expect(await coordinator.resumePoint(of: Self.episode, in: .normal) == 1234.5)
    }

    @Test("FR-PLAY-02, FR-MODE-05: a position belongs to the mode it was played in")
    func positionsArePerMode() async {
        let coordinator = coordinator

        await coordinator.played(Self.episode, to: 300, of: Self.hour, in: .kids, resting: true)

        #expect(await coordinator.resumePoint(of: Self.episode, in: .kids) == 300)
        #expect(await coordinator.resumePoint(of: Self.episode, in: .normal) == nil)
    }

    @Test("FR-PLAY-03: during playback the position goes to the store only; where playback rests, to the copy too")
    func restingIsKeptDurably() async {
        let coordinator = coordinator

        await coordinator.played(Self.episode, to: 10, of: Self.hour, in: .normal, resting: false)
        await coordinator.played(Self.episode, to: 20, of: Self.hour, in: .normal, resting: false)
        #expect(await store.noted.map(\.offset) == [10, 20])
        #expect(await store.kept.isEmpty)

        await coordinator.played(Self.episode, to: 25, of: Self.hour, in: .normal, resting: true)

        #expect(await store.kept.map(\.offset) == [25])
        #expect(await coordinator.resumePoint(of: Self.episode, in: .normal) == 25)
    }

    @Test("FR-PLAY-03: the interval is one named constant, and short enough to cost seconds")
    func intervalIsShort() {
        #expect(PlaybackCoordinator.interval > 0)
        #expect(PlaybackCoordinator.interval <= 15)
    }

    @Test("FR-PLAY-04: stopping just before the threshold leaves the episode unwatched, with its position")
    func beforeTheThresholdIsUnwatched() async {
        let coordinator = coordinator

        await coordinator.played(Self.episode, to: 3509, of: Self.hour, in: .normal, resting: true)

        let progress = await store.progress(of: Self.episode, in: .normal)
        #expect(progress?.isFinished == false)
        #expect(progress?.offset == 3509)
    }

    @Test("FR-PLAY-04: passing the threshold marks the episode watched at that moment, and durably")
    func passingTheThresholdFinishes() async {
        let coordinator = coordinator

        await coordinator.played(Self.episode, to: 3510, of: Self.hour, in: .normal, resting: false)

        let progress = await store.progress(of: Self.episode, in: .normal)
        #expect(progress?.finishedAt == clock.now)
        // Not left to the next pause: finishing is what the home page turns on.
        #expect(await store.kept.count == 1)
    }

    @Test("FR-PLAY-04: playback that runs on to the very end stays finished since it first passed the threshold")
    func runningOnKeepsTheFirstFinish() async {
        let coordinator = coordinator
        await coordinator.played(Self.episode, to: 3510, of: Self.hour, in: .normal, resting: false)
        let finished = clock.now

        clock.advance(by: .seconds(80))
        await coordinator.played(Self.episode, to: 3590, of: Self.hour, in: .normal, resting: false)
        await coordinator.playedToEnd(Self.episode, in: .normal)

        #expect(await store.progress(of: Self.episode, in: .normal)?.finishedAt == finished)
    }

    @Test("FR-PLAY-04: an episode of unknown duration is finished only by reaching its end")
    func unknownDurationFinishesAtTheEnd() async {
        let coordinator = coordinator

        await coordinator.played(Self.episode, to: 99_999, of: nil, in: .normal, resting: true)
        #expect(await store.progress(of: Self.episode, in: .normal)?.isFinished == false)

        await coordinator.playedToEnd(Self.episode, in: .normal)

        #expect(await store.progress(of: Self.episode, in: .normal)?.isFinished == true)
        #expect(await store.kept.count == 2)
    }

    @Test("FR-PLAY-02: something watched past the threshold starts from the beginning when played again")
    func finishedStartsFromTheBeginning() async {
        let coordinator = coordinator

        // Stopped in the credits.
        await coordinator.played(Self.episode, to: 3550, of: Self.hour, in: .normal, resting: true)

        #expect(await coordinator.resumePoint(of: Self.episode, in: .normal) == nil)
    }

    @Test("FR-PLAY-02, FR-HOME-07: watching something again keeps it watched, and can itself be resumed")
    func watchingAgainStaysWatched() async {
        let coordinator = coordinator
        await coordinator.playedToEnd(Self.episode, in: .normal)
        let finished = clock.now

        clock.advance(by: .seconds(86_400))
        await coordinator.played(Self.episode, to: 600, of: Self.hour, in: .normal, resting: true)

        #expect(await store.progress(of: Self.episode, in: .normal)?.finishedAt == finished)
        #expect(await coordinator.resumePoint(of: Self.episode, in: .normal) == 600)
    }

    @Test("FR-PLAY-10: a stream that never got going does not wipe the position it was to resume from")
    func failedStartKeepsThePosition() async {
        let coordinator = coordinator
        await coordinator.played(Self.episode, to: 1200, of: Self.hour, in: .normal, resting: true)

        await coordinator.played(Self.episode, to: 0, of: nil, in: .normal, resting: true)
        await coordinator.played(Self.episode, to: .nan, of: nil, in: .normal, resting: true)

        #expect(await coordinator.resumePoint(of: Self.episode, in: .normal) == 1200)
    }

    @Test("FR-HOME-06: a position is kept with the length of what was played, and keeps it when the player forgets")
    func durationIsKept() async {
        let coordinator = coordinator

        await coordinator.played(Self.episode, to: 900, of: Self.hour, in: .normal, resting: true)
        #expect(await store.progress(of: Self.episode, in: .normal)?.fraction == 0.25)

        await coordinator.played(Self.episode, to: 1800, of: .nan, in: .normal, resting: true)

        #expect(await store.progress(of: Self.episode, in: .normal)?.duration == Self.hour)
        #expect(await store.progress(of: Self.episode, in: .normal)?.fraction == 0.5)
    }
}
