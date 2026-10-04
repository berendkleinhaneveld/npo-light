//
//  StillWatchingTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// Asking whether anyone is still watching.
@MainActor
struct StillWatchingTests {
    private static let series = StubCatalogue.results.series[0]
    private static let first = StubCatalogue.seasons[0].id
    private static let episode = StubCatalogue.episodes(of: first)[0]
    private static let place = PlayOrigin.series(SeriesPlace(series: series, season: first))
    private static let hour = Duration.seconds(3600)

    private let playback = StubPlayback()
    private let clock = TestClock(now: Date(timeIntervalSince1970: 1_000_000))

    private func model(in mode: Mode = .normal,
                       waiting: (any Clocking)? = nil,
                       timings: @escaping () -> Timings = { Timings() }) -> PlayerModel {
        PlayerModel(playable: Self.episode,
                    origin: Self.place,
                    mode: mode,
                    starter: playback,
                    positions: PlaybackCoordinator(watched: .scripted(),
                                                   order: EpisodeOrder(catalogue: StubCatalogue()),
                                                   clock: clock),
                    clock: waiting ?? clock,
                    timings: timings)
    }

    private func isAsking(_ model: PlayerModel) -> Bool {
        if case .asking = model.state { return true }
        return false
    }

    private func isPlaying(_ model: PlayerModel) -> Bool {
        if case .playing = model.state { return true }
        return false
    }

    // MARK: When it asks

    @Test("FR-PLAY-08: normal mode asks after three hours of playback nobody touched, and not before")
    func normalModeAsksAfterThreeHours() async {
        let model = model()
        await model.start()

        clock.advance(by: Self.hour * 3 - .seconds(1))
        model.checkAttention()
        #expect(isPlaying(model))

        clock.advance(by: .seconds(1))
        model.checkAttention()

        #expect(isAsking(model))
        #expect(model.attentionLimit == 10800)
    }

    @Test("FR-PLAY-08: kids mode asks after one hour")
    func kidsModeAsksAfterAnHour() async {
        let model = model(in: .kids)
        await model.start()

        clock.advance(by: Self.hour)
        model.checkAttention()

        #expect(isAsking(model))
    }

    @Test("FR-PLAY-08, FR-SET-02: each mode uses its own setting, as it is when the question comes up")
    func limitsAreIndependentSettings() async {
        var timings = Timings()
        let kids = model(in: .kids, timings: { timings })
        let normal = model(in: .normal, timings: { timings })
        await kids.start()
        await normal.start()
        timings[.kidsStillWatching] = 7200

        clock.advance(by: Self.hour)
        kids.checkAttention()
        normal.checkAttention()

        #expect(isPlaying(kids))
        #expect(isPlaying(normal))
        #expect(normal.attentionLimit == 10800)
    }

    @Test("FR-PLAY-08: pausing, resuming or scrubbing starts the count again")
    func interactionRestartsTheCount() async {
        let model = model()
        await model.start()
        clock.advance(by: Self.hour * 2)

        model.interacted()
        clock.advance(by: Self.hour * 2)
        model.checkAttention()
        #expect(isPlaying(model))

        clock.advance(by: Self.hour)
        model.checkAttention()

        #expect(isAsking(model))
    }

    @Test("FR-PLAY-08: the next episode starting by itself does not start the count again")
    func autoplayDoesNotRestartTheCount() async {
        let model = model()
        await model.start()
        clock.advance(by: Self.hour * 2)

        await model.ended()
        // The player reports the new episode starting, as it reports a press.
        model.interacted()
        clock.advance(by: Self.hour)
        model.checkAttention()

        #expect(playback.requests.count == 2)
        #expect(isAsking(model))
    }

    // MARK: What the question does

    @Test("FR-PLAY-08: with no answer within the grace period playback stops, and the app goes home")
    func noAnswerStopsPlayback() async {
        let model = model()
        await model.start()
        clock.advance(by: Self.hour * 3)

        model.checkAttention()
        #expect(!model.isOver)
        await model.asking?.value

        #expect(model.isOver)
        #expect(model.wasLeftUnattended)
        #expect(clock.waits == Array(repeating: .seconds(1), count: Attention.grace))
    }

    @Test("FR-PLAY-08: confirming carries on with the same player, and starts the count again")
    func confirmingCarriesOn() async {
        let hooked = HookClock()
        let model = model(waiting: hooked)
        await model.start()
        var remaining: [Int] = []
        hooked.onWait { [model] in
            if case .asking(_, let left) = model.state { remaining.append(left) }
            // Answered with a few seconds gone.
            if remaining.count == 3 { model.keepWatching() }
        }
        hooked.advance(by: Self.hour * 3)

        model.checkAttention()
        await model.asking?.value

        #expect(remaining == [30, 29, 28])
        #expect(isPlaying(model))
        #expect(!model.isOver)
        // No new stream: it is the player that was held.
        #expect(playback.requests.count == 1)

        hooked.advance(by: Self.hour * 2)
        model.checkAttention()
        #expect(isPlaying(model))
    }

    @Test("FR-PLAY-08: stopping at the question ends the sitting, without going home")
    func stoppingAtTheQuestion() async {
        let model = model()
        await model.start()
        clock.advance(by: Self.hour * 3)
        model.checkAttention()

        model.stopGoingOn()

        #expect(model.isOver)
        #expect(!model.wasLeftUnattended)
    }

    @Test("FR-PLAY-08: a player that was closed while it asked does not send the app home")
    func closingWhileAsking() async {
        let model = model()
        await model.start()
        clock.advance(by: Self.hour * 3)
        model.checkAttention()

        model.stop()
        await model.asking?.value

        #expect(!model.wasLeftUnattended)
    }

    // MARK: Telling a press from the app's own doing

    @Test("FR-PLAY-08: what the player reports just after the app started or held it is not somebody's press")
    func ownChangesAreNotInteraction() {
        let start = Date(timeIntervalSince1970: 0)
        var attention = Attention(at: start)

        attention.expectOwnChange(at: start.addingTimeInterval(100))
        attention.noticed(at: start.addingTimeInterval(101))
        #expect(attention.since == start)

        attention.noticed(at: start.addingTimeInterval(100 + Attention.settling))

        #expect(attention.since == start.addingTimeInterval(100 + Attention.settling))
        #expect(attention.isDue(at: attention.since.addingTimeInterval(60), after: .seconds(60)))
        #expect(!attention.isDue(at: attention.since.addingTimeInterval(59), after: .seconds(60)))
    }
}
