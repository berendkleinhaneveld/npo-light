//
//  OffMainActorTests.swift
//  NPO lightTests
//

import Foundation
import Synchronization
import Testing
@testable import NPO_light

/// Whether the caller's actor is carried into the NPO boundary. A screen model
/// calls it from the main actor, and the request and its decoding must not
/// stay there.
@MainActor
struct OffMainActorTests {
    /// Records, per request, whether the transport was reached on the main thread.
    nonisolated private final class ThreadRecorder: Sendable {
        private let onMain = Mutex<[Bool]>([])

        var sawMainThread: Bool { onMain.withLock { $0.contains(true) } }
        var count: Int { onMain.withLock { $0.count } }

        func record() {
            let isMain = Thread.isMainThread
            onMain.withLock { $0.append(isMain) }
        }
    }

    @Test("FR-SEARCH-03, NFR-PERF-05: a search asked from the main actor is fetched and decoded off it")
    func searchLeavesTheMainActor() async throws {
        let recorder = ThreadRecorder()
        let search = try Fixture.data("search-200")
        let profiles = try Fixture.data("profiles-200")
        let harness = SignInHarness(backend: { request in
            recorder.record()
            switch request.url?.path {
            case "/profiles": return HTTPResponse(status: 200, body: profiles)
            case "/search": return HTTPResponse(status: 200, body: search)
            default: return .json(SignInHarness.premiumAccount)
            }
        })
        try await harness.signIn()
        let catalogue: any Catalogue = NPOCatalogue(authenticator: harness.authenticator)

        let results = try await catalogue.search(for: "fr", in: .normal)

        #expect(!results.isEmpty)
        #expect(recorder.count >= 3)
        #expect(!recorder.sawMainThread)
    }

    @Test("FR-CONTENT-02, NFR-PERF-05: series and season requests leave the main actor")
    func seriesLeavesTheMainActor() async throws {
        let recorder = ThreadRecorder()
        let series = try Fixture.data("series-page-200")
        let episodes = try Fixture.data("season-programs-200")
        let profiles = try Fixture.data("profiles-200")
        let harness = SignInHarness(backend: { request in
            recorder.record()
            switch request.url?.path {
            case "/profiles": return HTTPResponse(status: 200, body: profiles)
            case "/series/page/s-1": return HTTPResponse(status: 200, body: series)
            case "/series/seasons/season-1/programs": return HTTPResponse(status: 200, body: episodes)
            default: return .json(SignInHarness.premiumAccount)
            }
        })
        try await harness.signIn()
        let catalogue: any Catalogue = NPOCatalogue(authenticator: harness.authenticator)

        let detail = try await catalogue.series(ItemID(rawValue: "s-1"), in: .normal)
        let listed = try await catalogue.episodes(of: SeasonID(rawValue: "season-1"), in: .normal)

        #expect(!detail.seasons.isEmpty)
        #expect(listed.count == 3)
        #expect(recorder.count >= 4)
        #expect(!recorder.sawMainThread)
    }
}
