//
//  NPOPlayback.swift
//  NPO light
//

import AVFoundation
import AVKit
import Foundation
import Synchronization

/// A player with a protected stream loaded, and what has to stay alive for as
/// long as it plays.
@MainActor
struct Playback {
    let player: AVPlayer

    /// The content-key session and its delegate. AVFoundation holds neither
    /// strongly, so whoever holds the playback holds them.
    let keys: AnyObject?
}

/// Starting playback of one item, in the app's own terms (ADR 0008).
@MainActor
protocol PlaybackStarting {
    /// A player for `playable`, with stream details fetched now and not reused
    /// from an earlier playback (FR-PLAY-11).
    func playback(of playable: Playable, in mode: Mode) async throws -> Playback
}

/// Plays NPO's protected streams with the system player and the system's own
/// content-key handling.
@MainActor
final class NPOPlayback: PlaybackStarting {
    private let streams: NPOStreams
    private let licenser: FairPlayLicenser
    private let clock: any Clocking

    init(streams: NPOStreams, licenser: FairPlayLicenser, clock: any Clocking) {
        self.streams = streams
        self.licenser = licenser
        self.clock = clock
    }

    func playback(of playable: Playable, in mode: Mode) async throws -> Playback {
        #if targetEnvironment(simulator)
        // Creating the content-key session below raises an exception here,
        // which nothing can catch. Fail the way a stream fails instead.
        throw BackendError.protectionUnsupported
        #else
        try await protectedPlayback(of: playable, in: mode)
        #endif
    }

    private func protectedPlayback(of playable: Playable, in mode: Mode) async throws -> Playback {
        let stream = try await streams.stream(for: playable.id, in: mode)
        let asset = AVURLAsset(url: stream.manifest)

        let handler = FairPlayKeyHandler(protection: stream.protection,
                                         licenser: licenser,
                                         clock: clock) { [streams] in
            try await streams.stream(for: playable.id, in: mode).protection
        }
        let session = AVContentKeySession(keySystem: .fairPlayStreaming)
        session.setDelegate(handler, queue: handler.queue)
        session.addContentKeyRecipient(asset)

        let item = AVPlayerItem(asset: asset)
        item.externalMetadata = [Self.titleMetadata(playable.title)]
        return Playback(player: AVPlayer(playerItem: item), keys: KeySession(session: session, handler: handler))
    }

    /// The title the system player's info panel shows.
    private static func titleMetadata(_ title: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierTitle
        item.value = title as NSString
        item.extendedLanguageTag = "und"
        return item
    }
}

/// Keeps a content-key session and its delegate alive together.
private final class KeySession {
    let session: AVContentKeySession
    let handler: FairPlayKeyHandler

    init(session: AVContentKeySession, handler: FairPlayKeyHandler) {
        self.session = session
        self.handler = handler
    }
}

/// Answers the system's requests for a content key by carrying them to NPO's
/// licence gateway (FR-PLAY-11).
nonisolated final class FairPlayKeyHandler: NSObject, AVContentKeySessionDelegate, Sendable {
    let queue = DispatchQueue(label: "com.bearduck.NPO-light.content-keys")

    private let protection: Mutex<StreamProtection>
    private let licenser: FairPlayLicenser
    private let clock: any Clocking
    private let freshProtection: @Sendable () async throws -> StreamProtection

    init(protection: StreamProtection,
         licenser: FairPlayLicenser,
         clock: any Clocking,
         freshProtection: @escaping @Sendable () async throws -> StreamProtection) {
        self.protection = Mutex(protection)
        self.licenser = licenser
        self.clock = clock
        self.freshProtection = freshProtection
    }

    func contentKeySession(_ session: AVContentKeySession, didProvide keyRequest: AVContentKeyRequest) {
        answer(keyRequest, forRenewal: false)
    }

    /// A long playback outlives its licence. The credential that came with the
    /// stream is long spent by then, so the renewal gets one of its own and
    /// what is on screen is not interrupted.
    func contentKeySession(_ session: AVContentKeySession,
                           didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest) {
        answer(keyRequest, forRenewal: true)
    }

    private func answer(_ keyRequest: AVContentKeyRequest, forRenewal: Bool) {
        Task {
            do {
                let licence = try await self.licence(for: keyRequest, forRenewal: forRenewal)
                keyRequest.processContentKeyResponse(
                    AVContentKeyResponse(fairPlayStreamingKeyResponseData: licence)
                )
            } catch {
                // The player item fails with this, and the screen offers a retry.
                keyRequest.processContentKeyResponseError(error)
            }
        }
    }

    private func licence(for keyRequest: AVContentKeyRequest, forRenewal: Bool) async throws -> Data {
        guard let identifier = keyRequest.identifier as? String,
              let assetID = FairPlayLicenser.assetID(fromKeyIdentifier: identifier) else {
            throw BackendError.unexpectedResponse(status: nil)
        }
        var current = protection.withLock { $0 }
        if !FairPlayLicenser.isUsable(current, at: clock.now, forRenewal: forRenewal) {
            current = try await freshProtection()
            protection.withLock { [current] in $0 = current }
        }
        let certificate = try await licenser.certificate(for: current)
        let request = try await keyRequest.makeStreamingContentKeyRequestData(
            forApp: certificate,
            contentIdentifier: Data(assetID.utf8)
        )
        return try await licenser.licence(for: request, assetID: assetID, protection: current)
    }
}
