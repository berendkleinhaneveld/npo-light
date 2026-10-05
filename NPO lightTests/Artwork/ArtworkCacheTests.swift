//
//  ArtworkCacheTests.swift
//  NPO lightTests
//

import CoreGraphics
import Foundation
import Testing
@testable import NPO_light

struct ArtworkCacheTests {
    /// 100 × 100 pixels of four bytes each.
    private static let imageCost = 40_000

    private static func key(_ name: String) throws -> ArtworkCache.Key {
        ArtworkCache.Key(url: try #require(URL(string: "https://assets.example/\(name).jpg")), size: .tile)
    }

    private static func image() throws -> CGImage {
        try TestImage.image(width: 100, height: 100)
    }

    @Test("NFR-PERF-04: the artwork cache never holds more than its ceiling")
    func cacheStaysUnderItsCeiling() throws {
        var cache = ArtworkCache(ceiling: Self.imageCost * 3)

        for number in 1...10 {
            cache.insert(try Self.image(), for: try Self.key("\(number)"))
            #expect(cache.cost <= cache.ceiling)
        }

        #expect(cache.count == 3)
        #expect(cache.cost == Self.imageCost * 3)
    }

    @Test("NFR-PERF-04: the image used longest ago is the one that makes room")
    func leastRecentlyUsedGoesFirst() throws {
        var cache = ArtworkCache(ceiling: Self.imageCost * 2)
        cache.insert(try Self.image(), for: try Self.key("first"))
        cache.insert(try Self.image(), for: try Self.key("second"))

        // Looking at the first makes the second the older of the two.
        #expect(cache.image(for: try Self.key("first")) != nil)
        cache.insert(try Self.image(), for: try Self.key("third"))

        #expect(cache.image(for: try Self.key("first")) != nil)
        #expect(cache.image(for: try Self.key("second")) == nil)
        #expect(cache.image(for: try Self.key("third")) != nil)
    }

    @Test("NFR-PERF-04: an image kept twice is counted once")
    func replacingDoesNotCountTwice() throws {
        var cache = ArtworkCache(ceiling: Self.imageCost * 2)

        cache.insert(try Self.image(), for: try Self.key("same"))
        cache.insert(try Self.image(), for: try Self.key("same"))

        #expect(cache.count == 1)
        #expect(cache.cost == Self.imageCost)
    }

    @Test("NFR-PERF-04: an image larger than the whole ceiling is not kept")
    func tooLargeIsNotKept() throws {
        var cache = ArtworkCache(ceiling: Self.imageCost - 1)

        cache.insert(try Self.image(), for: try Self.key("large"))

        #expect(cache.isEmpty)
        #expect(cache.cost == 0)
    }

    @Test("NFR-PERF-04: the same image at two sizes is two entries")
    func sizesAreKeptApart() throws {
        var cache = ArtworkCache(ceiling: Self.imageCost * 2)
        let tile = try Self.key("same")
        let large = ArtworkCache.Key(url: tile.url, size: .large)

        cache.insert(try Self.image(), for: tile)

        #expect(cache.image(for: tile) != nil)
        #expect(cache.image(for: large) == nil)
    }
}
