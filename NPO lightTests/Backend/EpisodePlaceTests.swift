//
//  EpisodePlaceTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// Finding the series an episode belongs to, which a list does not name.
struct EpisodePlaceTests {
    private static let episode = EpisodeID(rawValue: "7a4c73be-b8e7-4ffd-a2c1-f7df7be3a918")
    private static let playerPath = "/programs/player/7a4c73be-b8e7-4ffd-a2c1-f7df7be3a918"

    private static func catalogue(player: HTTPResponse,
                                  page: HTTPResponse) async throws -> (NPOCatalogue, SignInHarness) {
        let profiles = try Fixture.data("profiles-200")
        let harness = SignInHarness(backend: { request in
            switch request.url?.path {
            case "/account": .json(SignInHarness.premiumAccount)
            case "/profiles": HTTPResponse(status: 200, body: profiles)
            case playerPath: player
            case "/series/page/by/slug/wisting": page
            default: .json("{}", status: 404)
            }
        })
        try await harness.signIn()
        return (NPOCatalogue(authenticator: harness.authenticator), harness)
    }

    @Test("FR-PLAY-09: an episode's series and season are what NPO answers to playing it, and that series' page")
    func episodeIsPlaced() async throws {
        let (catalogue, harness) = try await Self.catalogue(
            player: HTTPResponse(status: 200, body: Fixture.data("player-200")),
            page: HTTPResponse(status: 200, body: Fixture.data("series-page-200"))
        )

        let place = try #require(try await catalogue.place(of: Self.episode, in: .normal))

        // The series as its page names it, under the app's own identifier.
        #expect(place.series.id == ItemID(rawValue: "0806bc3a-3ad1-403c-aa4a-feac30c86ac4"))
        #expect(place.series.title == "Freeks wilde wereld")
        #expect(place.season == SeasonID(rawValue: "3737e7bb-b163-456a-b064-6160316f9cc7"))
        #expect(harness.backendRequests.contains { $0.url?.path == "/series/page/by/slug/wisting" })
    }

    @Test("FR-CONTENT-01: a programme that belongs to no series has no place in one, and no page is asked for")
    func singleProgrammeHasNoPlace() async throws {
        let (catalogue, harness) = try await Self.catalogue(
            player: .json(#"{"token":"t","program":{"guid":"p-1","programSlug":"film"}}"#),
            page: .json("{}", status: 404)
        )

        #expect(try await catalogue.place(of: Self.episode, in: .normal) == nil)
        #expect(!harness.backendRequests.contains { $0.url?.path.hasPrefix("/series/") == true })
    }

    @Test("FR-CONTENT-05: an episode NPO no longer has cannot be placed, and says so")
    func goneEpisodeIsUnavailable() async throws {
        let (catalogue, _) = try await Self.catalogue(player: .json("{}", status: 404), page: .json("{}", status: 404))

        await #expect(throws: BackendError.itemUnavailable) {
            _ = try await catalogue.place(of: Self.episode, in: .normal)
        }
    }
}
