//
//  SharedProgressTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// What NPO says was watched, read from the captured shapes (ADR 0009,
/// ADR 0028).
struct SharedProgressTests {
    private static let season = "/series/seasons/5069febe-66af-4757-9cc1-6683a99d0b90/programs"
    private static let player = "/programs/player/7c41b9e2-4bee-4003-8450-a59bee7c6830"

    /// A signed-in harness whose backend answers one path from a fixture.
    private static func harness(answering path: String, with fixture: String) async throws -> SignInHarness {
        let profiles = try Fixture.data("profiles-200")
        let body = try Fixture.data(fixture)
        let link = try Fixture.data("stream-link-200")
        let harness = SignInHarness(backend: { request in
            switch (request.url?.host, request.url?.path) {
            case ("prod.npoplayer.nl", _): HTTPResponse(status: 200, body: link)
            case (_, "/profiles"): HTTPResponse(status: 200, body: profiles)
            case (_, path): HTTPResponse(status: 200, body: body)
            default: .json(SignInHarness.premiumAccount)
            }
        })
        try await harness.signIn()
        return harness
    }

    @Test("FR-PLAY-13: an episode in a season's list carries the position NPO has for it, and only then")
    func seasonListCarriesPositions() async throws {
        let harness = try await Self.harness(answering: Self.season, with: "season-programs-progress-200")
        let catalogue = NPOCatalogue(authenticator: harness.authenticator)

        let episodes = try await catalogue.episodes(
            of: SeasonID(rawValue: "5069febe-66af-4757-9cc1-6683a99d0b90"),
            in: .normal
        )

        let position = try #require(episodes.first?.position)
        #expect(position.offset == 29.93982882)
        // The stream's own length: the position divided by the share NPO
        // says it is. The list itself gives none.
        #expect(abs(try #require(position.duration) - 2408.44) < 0.01)
        #expect(episodes.last?.position == nil)
    }

    @Test("FR-HOME-12: what NPO lists to go on with is read from its home page, and nothing else on it is")
    func continuingIsReadFromNPOsHome() async throws {
        let harness = try await Self.harness(answering: "/pages/by/slug/home", with: "home-200")
        let catalogue = NPOCatalogue(authenticator: harness.authenticator)

        let continuing = try await catalogue.continuing(in: .normal)

        #expect(continuing.map(\.playable.title) == ["A'dam - E.V.A.", "Sweet Dreams"])
        #expect(continuing.map(\.isSingle) == [false, true])
        #expect(continuing.first?.playable.caption == "46m • Afl. 5: De harmonie")
        #expect(continuing.first?.playable.position?.offset == 1316)
        let asked = harness.backendRequests.first { $0.url?.path == "/pages/by/slug/home" }
        #expect(asked?.value(forHTTPHeaderField: "profile-guid") == "00000000-0000-0000-0000-000000000011")
    }

    @Test("FR-HOME-13: taking something off NPO's row is a DELETE of it on that row, as the mode's profile")
    func discontinuingDeletesFromNPOsRow() async throws {
        let harness = try await Self.harness(answering: "/pages/by/slug/home", with: "home-200")
        let catalogue = NPOCatalogue(authenticator: harness.authenticator)
        let episode = EpisodeID(rawValue: "004abf1c-8e68-47c0-945b-367848f2a9ee")

        try await catalogue.discontinue(episode, in: .kids)

        // The row's name carries a version, so NPO's home page is asked what
        // it is called now.
        let delete = try #require(harness.backendRequests.first { $0.httpMethod == "DELETE" })
        #expect(delete.url?.path == "/collection/continue-watching-v0/004abf1c-8e68-47c0-945b-367848f2a9ee")
        #expect(delete.value(forHTTPHeaderField: "profile-guid") == "00000000-0000-0000-0000-000000000012")
        #expect(delete.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
        #expect(harness.backendRequests.filter { $0.url?.path == "/pages/by/slug/home" }.count == 1)

        try await catalogue.discontinue(episode, in: .kids)
        #expect(harness.backendRequests.filter { $0.url?.path == "/pages/by/slug/home" }.count == 1)
    }

    @Test("FR-HOME-13: with no such row at NPO there is nothing to take off, and nothing is asked for")
    func nothingToDiscontinueWithoutARow() async throws {
        let harness = try await Self.harness(answering: "/pages/by/slug/home", with: "search-200")
        let catalogue = NPOCatalogue(authenticator: harness.authenticator)

        try await catalogue.discontinue(EpisodeID(rawValue: "one"), in: .normal)

        #expect(!harness.backendRequests.contains { $0.httpMethod == "DELETE" })
    }

    @Test("FR-HOME-12: a home page without such a row has nothing to go on with")
    func homeWithoutTheRowIsEmpty() async throws {
        let harness = try await Self.harness(answering: "/pages/by/slug/home", with: "search-200")
        let catalogue = NPOCatalogue(authenticator: harness.authenticator)

        #expect(try await catalogue.continuing(in: .normal).isEmpty)
    }

    @Test("FR-PLAY-13: the stream of something NPO has a position for comes with that position")
    func streamCarriesNPOsPosition() async throws {
        let harness = try await Self.harness(answering: Self.player, with: "player-progress-200")
        let products = NPOProducts()
        let streams = NPOStreams(authenticator: harness.authenticator,
                                 profiles: NPOProfiles(authenticator: harness.authenticator),
                                 transport: harness.transport,
                                 products: products)
        let episode = EpisodeID(rawValue: "7c41b9e2-4bee-4003-8450-a59bee7c6830")

        let stream = try await streams.stream(for: episode, in: .normal)

        #expect(stream.position?.offset == 88.965560839)
        #expect(abs(try #require(stream.position?.duration) - 2886.16) < 0.01)
        // NPO's own name for it, which a report about it goes by.
        #expect(products.product(for: episode) == "AT_300024566")
    }

    @Test("FR-PLAY-13: a position of nothing, or one that is not a number, is no position")
    func emptyPositionIsNone() {
        #expect(ProgressBody(secondsWatched: 0, fractionWatched: 0).position(of: 600) == nil)
        #expect(ProgressBody(secondsWatched: nil, fractionWatched: 0.5).position(of: 600) == nil)
        // Without a share, the length the list gives is the best there is.
        #expect(ProgressBody(secondsWatched: 30, fractionWatched: nil).position(of: 600)
            == SharedPosition(offset: 30, duration: 600))
    }
}
