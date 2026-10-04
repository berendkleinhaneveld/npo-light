//
//  Artwork.swift
//  NPO light
//

import CoreGraphics
import Foundation

/// How large an image is wanted, in the sizes NPO's image host will make.
///
/// The host scales an image only for a handful of `dimensions` it knows; for
/// any other value it answers with the original, which is some three thousand
/// pixels wide. So the sizes are an enumeration, not a number (ADR 0017).
nonisolated enum ArtworkSize: Sendable, Hashable, CaseIterable {
    /// A tile in a row: 320 points wide, 640 pixels on a 4K television.
    case tile

    /// A series' header, or the episode previewed beside a list.
    case large

    /// The longest side, in pixels. The host fits the image inside a square of
    /// this size and keeps its shape.
    var pixels: Int {
        switch self {
        case .tile: 600
        case .large: 1200
        }
    }

    /// `url`, asking for this size.
    func address(of url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var query = (components.queryItems ?? []).filter { $0.name != Self.parameter }
        query.append(URLQueryItem(name: Self.parameter, value: "\(pixels)x\(pixels)"))
        components.queryItems = query
        return components.url ?? url
    }

    private static let parameter = "dimensions"
}

/// Why an image could not be shown. A tile draws its placeholder either way
/// (FR-CONTENT-01); the case is for the log.
nonisolated enum ArtworkError: Error, Equatable {
    /// The host answered with something other than the image.
    case notFound(status: Int)

    /// What arrived could not be read as an image.
    case unreadable
}

/// Images from NPO, ready to draw.
///
/// What comes back is already decoded and no larger than `size`, so that
/// putting it on screen costs the main actor nothing (NFR-PERF-05).
nonisolated protocol ArtworkProviding: Sendable {
    /// The image if it is in memory, without waiting. This is what lets a
    /// tile that comes back on screen draw at once instead of flashing its
    /// placeholder.
    func cached(_ url: URL, size: ArtworkSize) -> CGImage?

    func image(at url: URL, size: ArtworkSize) async throws -> CGImage
}

/// No images at all: every tile keeps its placeholder. What a view gets when
/// nothing was injected — a preview, or the app as a test launches it.
nonisolated struct NoArtwork: ArtworkProviding {
    func cached(_ url: URL, size: ArtworkSize) -> CGImage? { nil }

    func image(at url: URL, size: ArtworkSize) async throws -> CGImage {
        throw ArtworkError.unreadable
    }
}
