//
//  LoggedBoundaryTests.swift
//  NPO lightTests
//

import AVFoundation
import Foundation
import Testing
@testable import NPO_light

struct LoggedBoundaryTests {
    private static let episode = StubCatalogue.episodes(of: StubCatalogue.seasons[0].id)[0]

    @Test("NFR-DIAG-01: a catalogue call that fails is logged with its cause, and without what was searched for")
    func catalogueFailuresAreLogged() async {
        let log = RecordingLog()
        let catalogue = LoggedCatalogue(
            wrapping: StubCatalogue(answer: { _ in throw BackendError.unexpectedResponse(status: 503) }),
            log: log
        )

        await #expect(throws: BackendError.unexpectedResponse(status: 503)) {
            _ = try await catalogue.search(for: "freek", in: .kids)
        }

        #expect(log.entries == [
            RecordingLog.Entry(message: "search in kids failed: unexpectedResponse(status: Optional(503))",
                               level: .error,
                               category: .catalogue)
        ])
    }

    @Test("NFR-DIAG-01: a catalogue call that works is passed on and leaves nothing in the log")
    func successIsQuiet() async throws {
        let log = RecordingLog()
        let catalogue = LoggedCatalogue(wrapping: StubCatalogue(), log: log)

        let results = try await catalogue.search(for: "freek", in: .normal)
        let detail = try await catalogue.series(StubCatalogue.detail.id, in: .normal)
        let episodes = try await catalogue.episodes(of: StubCatalogue.seasons[0].id, in: .normal)

        #expect(results == StubCatalogue.results)
        #expect(detail == StubCatalogue.detail)
        #expect(episodes == StubCatalogue.episodes(of: StubCatalogue.seasons[0].id))
        #expect(log.entries.isEmpty)
    }

    @Test("NFR-DIAG-01: each way signing in fails is logged under the session")
    func signInFailuresAreLogged() async {
        let log = RecordingLog()
        let authenticator = LoggedAuthenticator(
            wrapping: StubAuthenticator(start: { throw BackendError.unreachable },
                                        approval: { _ in throw BackendError.signInExpired },
                                        restored: { throw BackendError.notSignedIn },
                                        signingOut: { throw BackendError.unexpectedResponse(status: nil) }),
            log: log
        )

        await #expect(throws: BackendError.unreachable) { _ = try await authenticator.startSignIn() }
        await #expect(throws: BackendError.signInExpired) {
            _ = try await authenticator.awaitApproval(of: StubAuthenticator.challenge)
        }
        await #expect(throws: BackendError.notSignedIn) { _ = try await authenticator.restoredAccount() }
        #expect(throws: BackendError.unexpectedResponse(status: nil)) { try authenticator.signOut() }

        #expect(log.messages == [
            "startSignIn failed: unreachable",
            "awaitApproval failed: signInExpired",
            "restoredAccount failed: notSignedIn",
            "signOut failed: unexpectedResponse(status: nil)"
        ])
        #expect(log.entries.allSatisfy { $0.level == .error && $0.category == .session })
    }

    @Test("NFR-DIAG-01: a call that was called off because its screen went away is not logged")
    func cancellationIsQuiet() async {
        let log = RecordingLog()
        let authenticator = LoggedAuthenticator(
            wrapping: StubAuthenticator(approval: { _ in throw CancellationError() }),
            log: log
        )

        await #expect(throws: CancellationError.self) {
            _ = try await authenticator.awaitApproval(of: StubAuthenticator.challenge)
        }

        #expect(log.entries.isEmpty)
    }

    @Test("NFR-DIAG-01: a playback that would not start is logged with the item and the cause")
    @MainActor
    func playbackThatWillNotStartIsLogged() async {
        let log = RecordingLog()
        let playback = LoggedPlayback(
            wrapping: StubPlayback { _, _ in throw BackendError.unexpectedResponse(status: 403) },
            log: log
        )

        await #expect(throws: BackendError.unexpectedResponse(status: 403)) {
            _ = try await playback.playback(of: Self.episode, in: .normal)
        }

        #expect(log.entries == [
            RecordingLog.Entry(
                message: "playback of season-1-1 in normal failed: unexpectedResponse(status: Optional(403))",
                level: .error,
                category: .playback
            )
        ])
    }

    @Test("NFR-DIAG-04: a stream the player gives up on is logged with the player's own reason",
          .timeLimit(.minutes(1)))
    @MainActor
    func aStreamThatStopsIsLogged() async throws {
        let log = RecordingLog()
        let playback = LoggedPlayback(wrapping: MissingStream(), log: log)

        // Held for the length of the test: the listening lasts as long as the
        // playback does.
        let started = try await playback.playback(of: Self.episode, in: .normal)
        let entry = try #require(await log.next())

        #expect(started.player.currentItem?.status == .failed)
        #expect(entry.level == .error)
        #expect(entry.category == .playback)
        #expect(entry.message.hasPrefix("playback of season-1-1 in normal stopped: "))
    }

    @Test("NFR-DIAG-04: what the player says is logged with what was underneath it")
    func underlyingErrorsAreKept() {
        let underlying = NSError(domain: "CoreMediaErrorDomain",
                                 code: -12_660,
                                 userInfo: [NSLocalizedDescriptionKey: "Forbidden"])
        let error = NSError(domain: AVFoundationErrorDomain,
                            code: -11_800,
                            userInfo: [NSLocalizedDescriptionKey: "The operation could not be completed",
                                       NSUnderlyingErrorKey: underlying])

        #expect(PlaybackLogFormat.failure(error, of: "playback of x in kids")
            == "playback of x in kids stopped: AVFoundationErrorDomain -11800: "
            + "The operation could not be completed (CoreMediaErrorDomain -12660: Forbidden)")
        #expect(PlaybackLogFormat.failure(nil, of: "playback of x in kids")
            == "playback of x in kids stopped: no error given")
    }
}

/// A `PlaybackStarting` whose player has a stream that is not there, so that
/// the system player fails by itself.
@MainActor
private struct MissingStream: PlaybackStarting {
    func playback(of playable: Playable, in mode: Mode) async throws -> Playback {
        let item = AVPlayerItem(url: URL(filePath: "/nowhere/\(UUID().uuidString).m3u8"))
        return Playback(player: AVPlayer(playerItem: item), keys: nil)
    }
}
