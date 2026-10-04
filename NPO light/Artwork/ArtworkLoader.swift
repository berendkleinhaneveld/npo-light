//
//  ArtworkLoader.swift
//  NPO light
//

import CoreGraphics
import Foundation
import ImageIO
import Synchronization

/// Fetches NPO's images at the size they are shown, decodes them off the main
/// actor, and keeps the decoded ones under a ceiling (ADR 0017, NFR-PERF-04,
/// NFR-PERF-05).
///
/// The system's own `AsyncImage` does none of the three: it fetched a
/// three-thousand-pixel original for a tile 320 points wide and left decoding
/// it to the moment it was drawn, on the main thread — which is what made the
/// keyboard stutter while a search's results arrived.
nonisolated final class ArtworkLoader: ArtworkProviding {
    /// 64 MB of decoded pixels: about eighty tiles, or twenty large images.
    static let defaultCeiling = 64 * 1024 * 1024

    private struct State {
        var cache: ArtworkCache
        var fetching: [ArtworkCache.Key: Task<CGImage, any Error>] = [:]
    }

    private enum Lookup {
        case cached(CGImage)
        case fetching(Task<CGImage, any Error>)
        case started(Task<CGImage, any Error>)
    }

    private let transport: any HTTPTransport
    private let log: any Logging
    private let state: Mutex<State>

    init(transport: any HTTPTransport, log: any Logging, ceiling: Int = ArtworkLoader.defaultCeiling) {
        self.transport = transport
        self.log = log
        state = Mutex(State(cache: ArtworkCache(ceiling: ceiling)))
    }

    /// How much the images in memory take, in bytes.
    var cost: Int { state.withLock { $0.cache.cost } }

    func cached(_ url: URL, size: ArtworkSize) -> CGImage? {
        let key = ArtworkCache.Key(url: url, size: size)
        return state.withLock { $0.cache.image(for: key) }
    }

    /// Tiles asking for the same image share one fetch. A tile that goes away
    /// does not call the fetch off: the image is small, and the text that
    /// replaced it in the search field is likely to want it again.
    @concurrent
    func image(at url: URL, size: ArtworkSize) async throws -> CGImage {
        let key = ArtworkCache.Key(url: url, size: size)
        let fetch = state.withLock { state -> Lookup in
            if let image = state.cache.image(for: key) { return .cached(image) }
            if let task = state.fetching[key] { return .fetching(task) }
            let task = Task { [transport] in
                try await Self.fetch(url, size: size, from: transport)
            }
            state.fetching[key] = task
            return .started(task)
        }
        switch fetch {
        case .cached(let image):
            return image
        case .fetching(let task):
            return try await task.value
        case .started(let task):
            return try await finish(task, for: key)
        }
    }

    private func finish(_ task: Task<CGImage, any Error>, for key: ArtworkCache.Key) async throws -> CGImage {
        do {
            let image = try await task.value
            state.withLock { state in
                state.fetching[key] = nil
                state.cache.insert(image, for: key)
            }
            return image
        } catch {
            state.withLock { $0.fetching[key] = nil }
            // The host and no more: the path names an image, and an image
            // says what was looked at.
            LoggedCall.record(error, from: "artwork from \(key.url.host() ?? "?")", in: .http, log: log)
            throw error
        }
    }

    @concurrent
    private static func fetch(_ url: URL,
                              size: ArtworkSize,
                              from transport: any HTTPTransport) async throws -> CGImage {
        let response = try await transport.reaching(URLRequest(url: size.address(of: url)))
        guard response.status == 200 else {
            throw ArtworkError.notFound(status: response.status)
        }
        return try decoded(response.body, fitting: size)
    }

    /// Decodes to pixels here and now, and to no more of them than `size`
    /// asks for — also when the host ignored the size and sent the original.
    private static func decoded(_ data: Data, fitting size: ArtworkSize) throws -> CGImage {
        let lazily = [kCGImageSourceShouldCache: false] as CFDictionary
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: size.pixels
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, lazily),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            throw ArtworkError.unreadable
        }
        return image
    }
}
