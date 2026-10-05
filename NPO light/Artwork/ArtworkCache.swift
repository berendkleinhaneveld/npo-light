//
//  ArtworkCache.swift
//  NPO light
//

import CoreGraphics
import Foundation

/// Decoded images under a fixed ceiling, least recently used out first
/// (NFR-PERF-04).
///
/// A value type with no lock of its own: ``ArtworkLoader`` keeps it behind
/// one.
nonisolated struct ArtworkCache {
    struct Key: Hashable {
        let url: URL
        let size: ArtworkSize
    }

    private struct Entry {
        let image: CGImage
        let cost: Int
        var lastUsed: UInt64
    }

    /// The most the images may take together, in bytes of decoded pixels.
    let ceiling: Int

    private(set) var cost = 0
    private var entries: [Key: Entry] = [:]
    private var uses: UInt64 = 0

    init(ceiling: Int) {
        self.ceiling = ceiling
    }

    var count: Int { entries.count }

    var isEmpty: Bool { entries.isEmpty }

    /// The image, which now counts as the most recently used.
    mutating func image(for key: Key) -> CGImage? {
        guard var entry = entries[key] else { return nil }
        uses += 1
        entry.lastUsed = uses
        entries[key] = entry
        return entry.image
    }

    /// Keeps `image`, and drops the least recently used until everything fits.
    /// An image larger than the whole ceiling is not kept at all.
    mutating func insert(_ image: CGImage, for key: Key) {
        let imageCost = image.bytesPerRow * image.height
        remove(key)
        guard imageCost <= ceiling else { return }
        uses += 1
        entries[key] = Entry(image: image, cost: imageCost, lastUsed: uses)
        cost += imageCost
        while cost > ceiling, let oldest = entries.min(by: { $0.value.lastUsed < $1.value.lastUsed }) {
            remove(oldest.key)
        }
    }

    private mutating func remove(_ key: Key) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        cost -= entry.cost
    }
}
