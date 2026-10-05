//
//  ManifestLoader.swift
//  NPO light
//

import AVFoundation
import Foundation

/// Answers the system player when it asks for the manifest and for the
/// playlists of the subtitles, which only the app can give it (ADR 0027).
/// Everything else — the video, the sound, the subtitle file itself — the
/// player fetches from NPO as it always did.
nonisolated final class ManifestLoader: NSObject, AVAssetResourceLoaderDelegate, Sendable {
    let queue = DispatchQueue(label: "com.bearduck.NPO-light.manifest")

    private let stream: PlayableStream
    private let duration: Duration
    private let transport: any HTTPTransport

    /// `nil` when the stream has nothing to add, or does not say how long it
    /// lasts: then NPO's manifest is played as it is.
    init?(stream: PlayableStream, transport: any HTTPTransport) {
        guard !stream.subtitles.isEmpty, let duration = stream.duration, duration > .zero else { return nil }
        self.stream = stream
        self.duration = duration
        self.transport = transport
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let address = loadingRequest.request.url, address.scheme == SubtitledManifest.scheme else {
            return false
        }
        Task {
            do {
                let text = try await self.answer(for: address)
                loadingRequest.dataRequest?.respond(with: Data(text.utf8))
                loadingRequest.finishLoading()
            } catch {
                // The player item fails with this, and the screen offers a retry.
                loadingRequest.finishLoading(with: error)
            }
        }
        return true
    }

    /// What is at `address`: a subtitle playlist, or the manifest.
    func answer(for address: URL) async throws -> String {
        if let index = SubtitledManifest.trackIndex(of: address) {
            guard stream.subtitles.indices.contains(index) else { throw BackendError.unexpectedResponse(status: nil) }
            return SubtitledManifest.playlist(for: stream.subtitles[index], lasting: duration)
        }
        let response = try await transport.reaching(URLRequest(url: stream.manifest))
        guard response.status == 200, let original = String(data: response.body, encoding: .utf8) else {
            throw BackendError.unexpectedResponse(status: response.status)
        }
        return SubtitledManifest.multivariant(original, from: stream.manifest, adding: stream.subtitles)
    }
}
