//
//  ArtworkLoaderTests.swift
//  NPO lightTests
//

import CoreGraphics
import Foundation
import Synchronization
import Testing
@testable import NPO_light

@MainActor
struct ArtworkLoaderTests {
    nonisolated private final class ThreadRecorder: Sendable {
        private let onMain = Mutex<[Bool]>([])

        var sawMainThread: Bool { onMain.withLock { $0.contains(true) } }

        func record() {
            let isMain = Thread.isMainThread
            onMain.withLock { $0.append(isMain) }
        }
    }

    private static func address(_ name: String = "image") throws -> URL {
        try #require(URL(string: "https://assets.example/resources/\(name).jpg"))
    }

    /// A host that answers every request with the same image.
    private static func host(width: Int = 3024, height: Int = 1701) throws -> StubTransport {
        let body = try TestImage.png(width: width, height: height)
        return StubTransport { _ in HTTPResponse(status: 200, body: body) }
    }

    @Test("NFR-PERF-05: artwork is asked for at the size it is shown, not as the original",
          arguments: [(ArtworkSize.tile, "600x600"), (ArtworkSize.large, "1200x1200")])
    func asksForTheSizeShown(size: ArtworkSize, dimensions: String) async throws {
        let transport = try Self.host()
        let loader = ArtworkLoader(transport: transport, log: RecordingLog())

        _ = try await loader.image(at: try Self.address(), size: size)

        let sent = try #require(transport.sent.first?.url)
        #expect(sent.path() == "/resources/image.jpg")
        #expect(sent.query() == "dimensions=\(dimensions)")
    }

    @Test("NFR-PERF-05: an image for the whole screen is the original, decoded no wider than the screen")
    func fullSizeIsTheOriginalScaledDown() async throws {
        let transport = try Self.host(width: 3024, height: 1701)
        let loader = ArtworkLoader(transport: transport, log: RecordingLog())

        let image = try await loader.image(at: try Self.address(), size: .full)

        // The host scales to no size between 1200 and the original, so it is
        // not asked to.
        #expect(transport.sent.first?.url == (try Self.address()))
        #expect(image.width == 1920)
        #expect(image.height == 1080)
    }

    @Test("NFR-PERF-05: an original that arrives anyway is decoded no larger than it is shown")
    func originalIsScaledDown() async throws {
        let loader = ArtworkLoader(transport: try Self.host(width: 3024, height: 1701), log: RecordingLog())

        let image = try await loader.image(at: try Self.address(), size: .tile)

        #expect(image.width == 600)
        #expect(image.height < 600)
    }

    @Test("NFR-PERF-05: artwork asked for from the main actor is fetched off it")
    func fetchLeavesTheMainActor() async throws {
        let recorder = ThreadRecorder()
        let body = try TestImage.png(width: 64, height: 36)
        let transport = StubTransport { _ in
            recorder.record()
            return HTTPResponse(status: 200, body: body)
        }
        let loader: any ArtworkProviding = ArtworkLoader(transport: transport, log: RecordingLog())

        _ = try await loader.image(at: try Self.address(), size: .tile)

        #expect(transport.sent.count == 1)
        #expect(!recorder.sawMainThread)
    }

    @Test("NFR-PERF-04: an image in memory is not fetched again, and is there without waiting")
    func secondAskIsFromMemory() async throws {
        let transport = try Self.host(width: 64, height: 36)
        let loader = ArtworkLoader(transport: transport, log: RecordingLog())
        let url = try Self.address()
        #expect(loader.cached(url, size: .tile) == nil)

        let first = try await loader.image(at: url, size: .tile)
        let second = try await loader.image(at: url, size: .tile)

        #expect(transport.sent.count == 1)
        #expect(first === second)
        #expect(loader.cached(url, size: .tile) === first)
    }

    @Test("NFR-PERF-04: images beyond the ceiling push the oldest out of memory")
    func memoryHasACeiling() async throws {
        let transport = try Self.host(width: 100, height: 100)
        let loader = ArtworkLoader(transport: transport, log: RecordingLog(), ceiling: 100_000)

        for number in 1...5 {
            _ = try await loader.image(at: try Self.address("\(number)"), size: .tile)
        }

        #expect(loader.cost <= 100_000)
        #expect(loader.cached(try Self.address("1"), size: .tile) == nil)
        #expect(loader.cached(try Self.address("5"), size: .tile) != nil)
    }

    @Test("NFR-PERF-04: tiles asking for one image at the same time share one fetch")
    func sameImageIsFetchedOnce() async throws {
        let transport = try Self.host(width: 64, height: 36)
        let loader = ArtworkLoader(transport: transport, log: RecordingLog())
        let url = try Self.address()

        async let first = loader.image(at: url, size: .tile)
        async let second = loader.image(at: url, size: .tile)
        async let third = loader.image(at: url, size: .tile)
        _ = try await (first, second, third)

        #expect(transport.sent.count == 1)
    }

    @Test("FR-CONTENT-01, NFR-DIAG-01: an image NPO does not have fails, is logged, and may be asked for again")
    func missingImageFails() async throws {
        let transport = StubTransport { _ in HTTPResponse(status: 404) }
        let log = RecordingLog()
        let loader = ArtworkLoader(transport: transport, log: log)
        let url = try Self.address("secret-title")

        await #expect(throws: ArtworkError.notFound(status: 404)) {
            try await loader.image(at: url, size: .tile)
        }
        await #expect(throws: ArtworkError.notFound(status: 404)) {
            try await loader.image(at: url, size: .tile)
        }

        #expect(transport.sent.count == 2)
        #expect(loader.cached(url, size: .tile) == nil)
        #expect(log.entries.count == 2)
        #expect(log.entries.allSatisfy { $0.level == .error && $0.category == .http })
        // The host, and not which image it was.
        #expect(log.messages.allSatisfy { $0.contains("assets.example") && !$0.contains("secret-title") })
    }

    @Test("FR-CONTENT-01: bytes that are not an image fail instead of drawing nothing")
    func unreadableImageFails() async throws {
        let transport = StubTransport { _ in HTTPResponse(status: 200, body: Data("<html>".utf8)) }
        let loader = ArtworkLoader(transport: transport, log: RecordingLog())

        await #expect(throws: ArtworkError.unreadable) {
            try await loader.image(at: try Self.address(), size: .tile)
        }
    }

    @Test("FR-CONTENT-01: with no source of images, a tile keeps its placeholder")
    func noArtworkHasNothing() async throws {
        let artwork = NoArtwork()
        let url = try Self.address()

        #expect(artwork.cached(url, size: .tile) == nil)
        await #expect(throws: ArtworkError.unreadable) {
            try await artwork.image(at: url, size: .tile)
        }
    }
}
