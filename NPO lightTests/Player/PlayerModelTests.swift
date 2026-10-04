//
//  PlayerModelTests.swift
//  NPO lightTests
//

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
        #expect(home.playing == Self.episode)

        home.playing = nil
        home.open(.playable(Self.episode))

        #expect(home.playing == Self.episode)
        #expect(home.path.isEmpty)
    }
}
