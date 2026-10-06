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

    /// The content-key session, its delegate and whoever answers for the
    /// manifest. AVFoundation holds none of them strongly, so whoever holds
    /// the playback holds them.
    let keys: AnyObject?

    /// How long NPO says it lasts, for as long as the player does not know
    /// yet.
    var duration: TimeInterval?

    /// Where NPO says it was left, if anywhere (FR-PLAY-13).
    var position: SharedPosition?
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
    private let transport: any HTTPTransport
    private let clock: any Clocking

    init(streams: NPOStreams, licenser: FairPlayLicenser, transport: any HTTPTransport, clock: any Clocking) {
        self.streams = streams
        self.licenser = licenser
        self.transport = transport
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
        // With subtitles to add, the player asks the app for the manifest
        // (ADR 0027); without, it fetches NPO's own.
        let loader = ManifestLoader(stream: stream, transport: transport)
        let asset = AVURLAsset(url: loader.flatMap { _ in SubtitledManifest.manifest } ?? stream.manifest)
        if let loader {
            asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        }
        let item = AVPlayerItem(asset: asset)
        item.externalMetadata = [Self.titleMetadata(playable.title)]
        // A stream NPO sends in the clear needs no keys, and so no session.
        guard let protection = stream.protection else {
            return Self.playback(AVPlayer(playerItem: item), of: stream, keeping: loader)
        }

        let handler = FairPlayKeyHandler(protection: protection,
                                         licenser: licenser,
                                         clock: clock) { [streams] in
            // A stream that was protected a moment ago still is.
            guard let fresh = try await streams.stream(for: playable.id, in: mode).protection else {
                throw BackendError.unexpectedResponse(status: nil)
            }
            return fresh
        }
        let session = AVContentKeySession(keySystem: .fairPlayStreaming)
        session.setDelegate(handler, queue: handler.queue)
        session.addContentKeyRecipient(asset)
        return Self.playback(AVPlayer(playerItem: item),
                             of: stream,
                             keeping: KeySession(session: session, handler: handler, loader: loader))
    }

    private static func playback(_ player: AVPlayer, of stream: PlayableStream, keeping keys: AnyObject?) -> Playback {
        Playback(player: player,
                 keys: keys,
                 duration: stream.duration?.timeInterval,
                 position: stream.position)
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

/// Keeps a content-key session, its delegate and the manifest's loader alive
/// together.
private final class KeySession {
    let session: AVContentKeySession
    let handler: FairPlayKeyHandler
    let loader: ManifestLoader?

    init(session: AVContentKeySession, handler: FairPlayKeyHandler, loader: ManifestLoader?) {
        self.session = session
        self.handler = handler
        self.loader = loader
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
