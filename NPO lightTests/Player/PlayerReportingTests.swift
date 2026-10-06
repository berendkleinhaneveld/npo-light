//
//  PlayerReportingTests.swift
//  NPO lightTests
//

import AVFoundation
import Foundation
import Testing
@testable import NPO_light

/// The player telling NPO what it plays, and taking over what NPO knows,
/// against the test card (ADR 0019, ADR 0028).
@MainActor
struct PlayerReportingTests {
    private static let episode = StubCatalogue.episodes(of: StubCatalogue.seasons[0].id)[0]

    /// Plays the test card, and says of it what NPO would say of a stream.
    private struct CardPlayback: PlaybackStarting {
        var position: SharedPosition?

        func playback(of playable: Playable, in mode: Mode) async throws -> Playback {
            let item = AVPlayerItem(url: try await TestCard.video())
            return Playback(player: AVPlayer(playerItem: item),
                            keys: nil,
                            duration: TimeInterval(TestCard.duration),
                            position: position)
        }
    }

    private let reporter = RecordingReports()
    private let store = ScriptedProgress()

    private func model(leftAt position: TimeInterval? = nil, in mode: Mode = .normal) -> PlayerModel {
        let watched = WatchedState(progress: store, history: ScriptedWatchHistory(), later: ScriptedWatchLater())
        let length = TimeInterval(TestCard.duration)
        let known = position.map { SharedPosition(offset: $0, duration: length) }
        return PlayerModel(playable: Self.episode,
                           origin: .single,
                           mode: mode,
                           starter: CardPlayback(position: known),
                           positions: PlaybackCoordinator(watched: watched,
                                                          order: EpisodeOrder(catalogue: StubCatalogue()),
                                                          clock: TestClock()),
                           clock: TestClock(),
                           reports: PlaybackReports(reporter: reporter))
    }

    private func playhead(of model: PlayerModel) -> TimeInterval? {
        guard case .playing(let playback) = model.state else { return nil }
        return playback.player.currentTime().seconds
    }

    @Test("FR-PLAY-13: something NPO has a position for resumes there, with nothing stored on the television")
    func resumesWhereNPOSaysItWasLeft() async throws {
        let model = model(leftAt: 60)

        await model.start()
        let position = try #require(playhead(of: model))
        model.stop()

        #expect(abs(position - 60) < 2)
    }

    @Test("FR-PLAY-12: starting tells NPO what plays, from where, how long it is and in which mode")
    func startingIsReported() async throws {
        let model = model(leftAt: 60, in: .kids)

        await model.start()
        await model.reports?.sending?.value
        model.stop()

        #expect(reporter.kinds.prefix(2) == [.loaded, .started])
        let started = try #require(reporter.reports.first)
        #expect(started.mode == .kids)
        #expect(started.event.episode == Self.episode.id)
        #expect(abs(started.event.position - 60) < 2)
        #expect(abs(started.event.duration - TimeInterval(TestCard.duration)) < 1)
    }

    @Test("FR-PLAY-12: leaving the player tells NPO where it was left")
    func leavingIsReported() async throws {
        let model = model(leftAt: 60)
        await model.start()

        await model.close()
        await model.reports?.sending?.value

        let last = try #require(reporter.reports.last)
        #expect(last.event.kind == .stopped)
        #expect(abs(last.event.position - 60) < 2)
    }

    @Test("FR-PLAY-12: moving through what plays tells NPO where from and where to")
    func movingIsReported() async throws {
        let model = model()
        await model.start()

        model.sought(from: 5, to: 120)
        await model.reports?.sending?.value
        model.stop()

        let sought = try #require(reporter.reports.first { $0.event.kind == .sought(from: 5) })
        #expect(sought.event.position == 120)
    }

    @Test("FR-PLAY-12: reaching the end tells NPO so")
    func endIsReported() async {
        let model = model()
        await model.start()

        await model.ended()
        await model.reports?.sending?.value

        #expect(reporter.kinds.contains(.completed))
    }

    @Test("FR-PLAY-12: a stream that does not start tells NPO nothing")
    func failedStartIsNotReported() async {
        let model = PlayerModel(playable: Self.episode,
                                mode: .normal,
                                starter: StubPlayback { _, _ in throw BackendError.unreachable },
                                positions: .scripted(),
                                clock: TestClock(),
                                reports: PlaybackReports(reporter: reporter))

        await model.start()
        model.stop()
        await model.reports?.sending?.value

        #expect(reporter.reports.isEmpty)
    }

    @Test("FR-PLAY-12: a player that tells NPO nothing plays all the same")
    func playsWithoutReports() async {
        let model = PlayerModel(playable: Self.episode, mode: .normal, starter: CardPlayback())

        await model.start()
        model.stop()

        #expect(model.reports == nil)
        #expect(model.problem == nil)
    }
}
