//
//  CatalogueTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// The catalogue client, held to the captured shapes (ADR 0009, ADR 0014).
struct CatalogueTests {
    private static let generalProfile = "00000000-0000-0000-0000-000000000011"
    private static let kidsProfile = "00000000-0000-0000-0000-000000000012"
    private static let onlyGeneral = """
    [{"guid":"00000000-0000-0000-0000-000000000011","type":"GENERAL","targetGroup":"GENERAL"}]
    """

    /// A signed-in authenticator whose backend answers each path from a fixture.
    private static func catalogue(
        profiles: String? = nil,
        answering path: String = "",
        with response: HTTPResponse = .json("{}")
    ) async throws -> (NPOCatalogue, SignInHarness) {
        let profilesBody = try profiles.map { Data($0.utf8) } ?? Fixture.data("profiles-200")
        let harness = SignInHarness(backend: { request in
            switch request.url?.path {
            case "/account": .json(SignInHarness.premiumAccount)
            case "/profiles": HTTPResponse(status: 200, body: profilesBody)
            case path: response
            default: .json("{}", status: 404)
            }
        })
        try await harness.signIn()
        return (NPOCatalogue(authenticator: harness.authenticator), harness)
    }

    private static func fixture(_ name: String) throws -> HTTPResponse {
        HTTPResponse(status: 200, body: try Fixture.data(name))
    }

    private static func requests(to path: String, in harness: SignInHarness) -> [URLRequest] {
        harness.backendRequests.filter { $0.url?.path == path }
    }

    // MARK: modes and profiles

    @Test("FR-MODE-04: an account with an NPO kids profile can use both modes")
    func kidsProfileOffersKidsMode() async throws {
        let (catalogue, _) = try await Self.catalogue()

        #expect(try await catalogue.availableModes() == [.normal, .kids])
    }

    @Test("FR-MODE-04: without an NPO kids profile only normal mode is available")
    func noKidsProfileMeansNormalOnly() async throws {
        let (catalogue, _) = try await Self.catalogue(profiles: Self.onlyGeneral)

        #expect(try await catalogue.availableModes() == [.normal])
        await #expect(throws: BackendError.kidsProfileMissing) {
            _ = try await catalogue.search(for: "fr", in: .kids)
        }
    }

    @Test("FR-MODE-04, FR-SEARCH-08: each mode asks as its own NPO profile, on the request itself", arguments: [
        (Mode.normal, "00000000-0000-0000-0000-000000000011"),
        (Mode.kids, "00000000-0000-0000-0000-000000000012")
    ])
    func modeSelectsTheProfile(mode: Mode, profile: String) async throws {
        let (catalogue, harness) = try await Self.catalogue(answering: "/search",
                                                            with: try Self.fixture("search-200"))

        _ = try await catalogue.search(for: "fr", in: mode)

        let request = try #require(Self.requests(to: "/search", in: harness).first)
        #expect(request.value(forHTTPHeaderField: "profile-guid") == profile)
    }

    @Test func profilesAreAskedForOncePerSignIn() async throws {
        let (catalogue, harness) = try await Self.catalogue(answering: "/search",
                                                            with: try Self.fixture("search-200"))

        _ = try await catalogue.search(for: "fr", in: .normal)
        _ = try await catalogue.search(for: "fre", in: .kids)

        #expect(Self.requests(to: "/profiles", in: harness).count == 1)
        #expect(Self.requests(to: "/profiles", in: harness).first?
            .value(forHTTPHeaderField: "profile-guid") == nil)
    }

    @Test func anotherSignInAsksForItsOwnProfiles() async throws {
        let (catalogue, harness) = try await Self.catalogue(answering: "/search",
                                                            with: try Self.fixture("search-200"))
        _ = try await catalogue.search(for: "fr", in: .normal)

        try harness.authenticator.signOut()
        try await harness.signIn()
        _ = try await catalogue.search(for: "fr", in: .normal)

        #expect(Self.requests(to: "/profiles", in: harness).count == 2)
    }

    // MARK: search

    @Test("FR-SEARCH-02: a search answers with series and playable items, each recognisable")
    func searchAnswersWithBothKinds() async throws {
        let (catalogue, harness) = try await Self.catalogue(answering: "/search",
                                                            with: try Self.fixture("search-200"))

        let results = try await catalogue.search(for: "fr", in: .normal)

        #expect(results.series.count == 2)
        #expect(results.singleProgrammes.isEmpty)
        #expect(results.episodes.count == 2)
        let series = try #require(results.series.first)
        #expect(series.id == ItemID(rawValue: "0806bc3a-3ad1-403c-aa4a-feac30c86ac4"))
        #expect(series.title == "Freeks wilde wereld")
        // The header image, not the transparent title logo listed before it.
        #expect(series.artwork?.pathExtension == "jpg")
        let playable = try #require(results.episodes.first)
        #expect(playable.id == EpisodeID(rawValue: "50a874df-bd47-4531-b595-8b385596bcd7"))
        #expect(playable.caption == "10m • Afl. 5: Haaien in de rivier")
        #expect(playable.duration == .seconds(628))
        let request = try #require(Self.requests(to: "/search", in: harness).first)
        #expect(request.url?.query() == "query=fr&page=1")
    }

    @Test("FR-SEARCH-10, FR-CONTENT-01: a programme that belongs to no series is kept apart from the episodes")
    func singleProgrammesAreKeptApart() async throws {
        let (catalogue, _) = try await Self.catalogue(answering: "/search",
                                                      with: try Self.fixture("search-single-programme-200"))

        let results = try await catalogue.search(for: "subst", in: .normal)

        #expect(results.series.map(\.title) == ["A Woman of Substance"])
        #expect(results.singleProgrammes.map(\.title) == ["The Substance"])
        #expect(results.singleProgrammes.first?.caption == "2u 9m")
        #expect(results.episodes.map(\.caption) == ["46m • Afl. 1", "46m • Afl. 7"])
    }

    @Test("FR-SEARCH-10: a programme that does not say where it leads is taken for an episode")
    func unmarkedProgrammesAreEpisodes() async throws {
        let body = """
        {"guid":"search","collections":[{"guid":"search-programs","items":[
        {"guid":"a","type":"program","title":"Zonder doel"},
        {"guid":"b","type":"program","title":"Met een ander doel","target":"elders"}]}]}
        """
        let (catalogue, _) = try await Self.catalogue(answering: "/search", with: .json(body))

        let results = try await catalogue.search(for: "doel", in: .normal)

        #expect(results.singleProgrammes.isEmpty)
        #expect(results.episodes.map(\.title) == ["Zonder doel", "Met een ander doel"])
    }

    @Test("FR-SEARCH-09: a search that matches nothing answers with nothing, not with an error")
    func emptySearchIsEmpty() async throws {
        let (catalogue, _) = try await Self.catalogue(
            answering: "/search",
            with: .json(#"{"guid":"search","collections":[{"guid":"search-series","items":[]}]}"#)
        )

        #expect(try await catalogue.search(for: "qqq", in: .normal).isEmpty)
    }

    @Test("FR-SEARCH-09: a search that fails on the network is told apart from no results")
    func failedSearchIsNotEmpty() async throws {
        let harness = SignInHarness(backend: { request in
            if request.url?.path == "/search" { throw URLError(.timedOut) }
            return request.url?.path == "/profiles"
                ? .json(Self.onlyGeneral)
                : .json(SignInHarness.premiumAccount)
        })
        try await harness.signIn()
        let catalogue = NPOCatalogue(authenticator: harness.authenticator)

        await #expect(throws: BackendError.unreachable) {
            _ = try await catalogue.search(for: "fr", in: .normal)
        }
    }

    @Test("FR-CONTENT-01: an item without artwork is still an item")
    func missingArtworkIsAllowed() async throws {
        let (catalogue, _) = try await Self.catalogue(
            answering: "/search",
            with: .json(#"{"collections":[{"items":[{"guid":"s-1","type":"series","title":"Zonder beeld"}]}]}"#)
        )

        let results = try await catalogue.search(for: "zonder", in: .normal)

        #expect(results.series == [SeriesSummary(id: ItemID(rawValue: "s-1"), title: "Zonder beeld", artwork: nil)])
    }

    @Test func otherKindsOfItemAreLeftOut() async throws {
        let (catalogue, _) = try await Self.catalogue(
            answering: "/search",
            with: .json(#"{"collections":[{"items":[{"guid":"p-1","type":"page","title":"Collectie"}]}]}"#)
        )

        #expect(try await catalogue.search(for: "collectie", in: .normal).isEmpty)
    }

    // MARK: series and seasons

    @Test("FR-CONTENT-02: a series exposes its seasons in NPO's order, named as NPO names them")
    func seriesExposesItsSeasons() async throws {
        let path = "/series/page/0806bc3a-3ad1-403c-aa4a-feac30c86ac4"
        let (catalogue, harness) = try await Self.catalogue(answering: path,
                                                            with: try Self.fixture("series-page-200"))

        let series = try await catalogue.series(ItemID(rawValue: "0806bc3a-3ad1-403c-aa4a-feac30c86ac4"),
                                                in: .kids)

        #expect(series.title == "Freeks wilde wereld")
        #expect(series.synopsis?.isEmpty == false)
        #expect(series.artwork != nil)
        #expect(series.seasons.count == 13)
        #expect(series.seasons.first?.title == "Seizoen 1")
        // The twelfth entry is not "Seizoen 12": the titles are editorial.
        #expect(series.seasons.suffix(2).map(\.title) == ["Kort", "Seizoen 12"])
        #expect(Self.requests(to: path, in: harness).first?
            .value(forHTTPHeaderField: "profile-guid") == Self.kidsProfile)
    }

    @Test("FR-CONTENT-02: a season exposes its episodes in broadcast order")
    func seasonExposesItsEpisodes() async throws {
        let path = "/series/seasons/078e0a22-afac-41ec-939d-a6191b45b1be/programs"
        let (catalogue, harness) = try await Self.catalogue(answering: path,
                                                            with: try Self.fixture("season-programs-200"))

        let episodes = try await catalogue.episodes(
            of: SeasonID(rawValue: "078e0a22-afac-41ec-939d-a6191b45b1be"),
            in: .normal
        )

        #expect(episodes.count == 3)
        let first = try #require(episodes.first)
        #expect(first.id == EpisodeID(rawValue: "10c84845-36e5-400d-9ac0-1e68109cef8e"))
        #expect(first.title == "Freek tussen de wolven")
        #expect(first.caption == "Afl. 1 • 10m")
        #expect(first.duration == nil)
        let request = try #require(Self.requests(to: path, in: harness).first)
        #expect(request.url?.query() == "sort=asc")
        #expect(request.value(forHTTPHeaderField: "profile-guid") == Self.generalProfile)
    }

    @Test("FR-CONTENT-05: a series NPO no longer has is reported as unavailable")
    func missingSeriesIsUnavailable() async throws {
        let (catalogue, _) = try await Self.catalogue()

        await #expect(throws: BackendError.itemUnavailable) {
            _ = try await catalogue.series(ItemID(rawValue: "gone"), in: .normal)
        }
    }
}
