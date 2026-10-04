//
//  PlayerModelTests.swift
//  NPO lightTests
//

import AVFoundation
import Foundation
import Testing
@testable import NPO_light

@MainActor
struct PlayerModelTests {
    private static let episode = StubCatalogue.episodes(of: StubCatalogue.seasons[0].id)[0]

    private var isPlaying: (PlayerModel) -> Bool {
        { model in
            if case .playing = model.state { return true }
            return false
        }
    }

    @Test("FR-PLAY-11: starting asks for the item's own stream, in the mode it is played in")
    func startAsksForTheStream() async {
        let playback = StubPlayback()
        let model = PlayerModel(playable: Self.episode, mode: .kids, starter: playback)

        await model.start()

        #expect(isPlaying(model))
        #expect(playback.requests.count == 1)
        #expect(playback.requests.first?.playable == Self.episode)
        #expect(playback.requests.first?.mode == .kids)
    }

    @Test("FR-PLAY-10: each way playback fails to start has its own message", arguments: [
        (BackendError.itemUnavailable, PlayerModel.Problem.unavailable),
        (BackendError.unreachable, PlayerModel.Problem.unreachable),
        (BackendError.unexpectedResponse(status: 403), PlayerModel.Problem.failed)
    ])
    func failuresAreToldApart(error: BackendError, problem: PlayerModel.Problem) async {
        let model = PlayerModel(playable: Self.episode,
                                mode: .normal,
                                starter: StubPlayback { _, _ in throw error })

        await model.start()

        #expect(model.problem == problem)
    }

    @Test("FR-PLAY-10, FR-PLAY-11: a retry fetches fresh stream details instead of reusing the old ones")
    func retryFetchesAgain() async {
        var attempts = 0
        let playback = StubPlayback { _, _ in
            attempts += 1
            if attempts == 1 { throw BackendError.unreachable }
        }
        let model = PlayerModel(playable: Self.episode, mode: .normal, starter: playback)

        await model.start()
        #expect(model.problem == .unreachable)

        await model.start()

        #expect(isPlaying(model))
        #expect(model.problem == nil)
        #expect(playback.requests.count == 2)
    }

    @Test("FR-PLAY-10: closing the player while it prepares reports no problem")
    func closingWhilePreparingIsQuiet() async {
        let model = PlayerModel(playable: Self.episode,
                                mode: .normal,
                                starter: StubPlayback { _, _ in throw CancellationError() })

        await model.start()

        #expect(model.problem == nil)
        #expect(!isPlaying(model))
    }

    @Test("FR-PLAY-01: an episode chosen in a series, or a playable search result, opens the player")
    func choosingSomethingPlayableOpensThePlayer() {
        let home = HomeModel(pins: ScriptedPins(), mode: .normal)

        home.play(Self.episode)
        #expect(home.playing?.playable == Self.episode)

        home.playing = nil
        home.open(.playable(Self.episode))

        #expect(home.playing == PlayRequest(playable: Self.episode, origin: .unknown))
        #expect(home.path.isEmpty)

        // A programme that belongs to no series opens its own page instead
        // (FR-CONTENT-03).
        home.playing = nil
        home.open(.single(Self.episode))

        #expect(home.playing == nil)
        #expect(home.path == [.programme(Self.episode)])
    }

    // MARK: With something to play

    /// A model that plays the test card, over positions a test can read.
    private static func coordinator(_ store: ScriptedProgress,
                                    _ history: ScriptedWatchHistory,
                                    catalogue: StubCatalogue = StubCatalogue()) -> PlaybackCoordinator {
        PlaybackCoordinator(watched: WatchedState(progress: store, history: history, later: ScriptedWatchLater()),
                            order: EpisodeOrder(catalogue: catalogue),
                            clock: TestClock())
    }

    private func cardModel(_ store: ScriptedProgress,
                           history: ScriptedWatchHistory = ScriptedWatchHistory(),
                           origin: PlayOrigin = .unknown,
                           mode: Mode = .normal) -> PlayerModel {
        PlayerModel(playable: Self.episode,
                    origin: origin,
                    mode: mode,
                    starter: ScriptedPlayback(),
                    positions: Self.coordinator(store, history),
                    clock: TestClock())
    }

    private func playhead(of model: PlayerModel) -> TimeInterval? {
        guard case .playing(let playback) = model.state else { return nil }
        return playback.player.currentTime().seconds
    }

    private static func stopped(at offset: TimeInterval) -> PlaybackProgress {
        PlaybackProgress(id: episode.id, offset: offset, finishedAt: nil, updatedAt: Date(timeIntervalSince1970: 0))
    }

    @Test("FR-PLAY-02: the player is moved to the stored position before it starts")
    func playerStartsAtTheStoredPosition() async throws {
        let model = cardModel(ScriptedProgress([Self.stopped(at: 60)]))

        await model.start()
        let position = try #require(playhead(of: model))
        model.stop()

        // Within a second of where it stopped.
        #expect(abs(position - 60) < 1)
    }

    @Test("FR-PLAY-02: something with no stored position starts at the beginning")
    func playerStartsAtTheBeginning() async throws {
        let model = cardModel(ScriptedProgress())

        await model.start()
        let position = try #require(playhead(of: model))
        model.stop()

        #expect(position < 1)
    }

    @Test("FR-PLAY-02, FR-MODE-05: a position from the other mode is not resumed")
    func otherModesPositionIsNotResumed() async throws {
        let model = cardModel(ScriptedProgress([Self.stopped(at: 60)], in: .kids), mode: .normal)

        await model.start()
        let position = try #require(playhead(of: model))
        model.stop()

        #expect(position < 1)
    }

    @Test("FR-PLAY-03: closing the player writes where it was, durably")
    func closingWritesThePosition() async throws {
        let store = ScriptedProgress([Self.stopped(at: 60)])
        let model = cardModel(store)
        await model.start()

        model.stop()
        await model.writing?.value

        let kept = try #require(await store.kept.last)
        #expect(kept.id == Self.episode.id)
        #expect(abs((kept.offset ?? 0) - 60) < 2)
        #expect(!kept.isFinished)
    }

    @Test("FR-PLAY-10: a player closed before anything played leaves the stored position alone")
    func closingAtTheStartWritesNothing() async {
        let store = ScriptedProgress()
        let model = cardModel(store)
        await model.start()

        model.stop()
        await model.writing?.value

        // The test card has not got past its first frame.
        #expect(await store.kept.allSatisfy { ($0.offset ?? 0) < 2 })
        #expect(await store.progress(of: Self.episode.id, in: .normal)?.isFinished != true)
    }

    @Test("NFR-MAINT-04: the test card is a playable video of the length it says, made without a network")
    func testCardIsPlayable() async throws {
        let asset = AVURLAsset(url: try await TestCard.video())

        let duration = try await asset.load(.duration).seconds
        let isPlayable = try await asset.load(.isPlayable)

        #expect(isPlayable)
        #expect(abs(duration - TimeInterval(TestCard.duration)) < 1)
    }

    @Test("FR-PLAY-09: a stream that starts makes its series continue with that episode")
    func startingRecordsTheSeries() async {
        let history = ScriptedWatchHistory()
        let place = SeriesPlace(series: StubCatalogue.results.series[0], season: StubCatalogue.seasons[0].id)
        let model = cardModel(ScriptedProgress(), history: history, origin: .series(place))

        await model.start()
        model.stop()

        #expect(await history.entry(for: place.series.id, in: .normal)?.next?.id == Self.episode.id)
    }

    @Test("FR-PLAY-09: a stream that does not start records nothing")
    func failedStartRecordsNothing() async {
        let history = ScriptedWatchHistory()
        let place = SeriesPlace(series: StubCatalogue.results.series[0], season: StubCatalogue.seasons[0].id)
        let model = PlayerModel(playable: Self.episode,
                                origin: .series(place),
                                mode: .normal,
                                starter: StubPlayback { _, _ in throw BackendError.unreachable },
                                positions: Self.coordinator(ScriptedProgress(), history),
                                clock: TestClock())

        await model.start()

        #expect(await history.entries(in: .normal).isEmpty)
    }

    @Test("FR-HOME-10: once the player has closed, where it stopped has been written")
    func closingWritesBeforeItReturns() async throws {
        let store = ScriptedProgress([Self.stopped(at: 60)])
        let model = cardModel(store)
        await model.start()

        await model.close()

        let offset = try #require(await store.kept.last?.offset)
        #expect(offset >= 59)
    }

    @Test("FR-PLAY-09: an episode started from search joins its series once it plays")
    func episodeFromSearchJoinsItsSeries() async {
        let history = ScriptedWatchHistory()
        let place = SeriesPlace(series: StubCatalogue.results.series[0], season: StubCatalogue.seasons[0].id)
        let catalogue = StubCatalogue(place: { _ in place })
        let model = PlayerModel(playable: Self.episode,
                                origin: .unknown,
                                mode: .normal,
                                starter: StubPlayback(),
                                positions: Self.coordinator(ScriptedProgress(), history, catalogue: catalogue),
                                clock: TestClock())

        await model.start()

        #expect(model.origin == .series(place))
        #expect(await history.entry(for: place.series.id, in: .normal)?.next?.id == Self.episode.id)
    }
}
