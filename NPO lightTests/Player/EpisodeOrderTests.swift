//
//  EpisodeOrderTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

struct EpisodeOrderTests {
    private static let first = StubCatalogue.seasons[0].id
    private static let second = StubCatalogue.seasons[1].id

    private static func place(in season: SeasonID, of seasons: [SeasonID] = [first, second]) -> SeriesPlace {
        SeriesPlace(series: StubCatalogue.results.series[0], seasons: seasons, season: season)
    }

    private static func episode(_ number: Int, of season: SeasonID) -> Playable {
        StubCatalogue.episodes(of: season)[number - 1]
    }

    @Test("FR-CONTENT-02: an episode is followed by the next one of its season")
    func nextInTheSeason() async throws {
        let order = EpisodeOrder(catalogue: StubCatalogue())

        let next = try await order.following(Self.episode(1, of: Self.first).id,
                                             at: Self.place(in: Self.first),
                                             in: .normal)

        #expect(next == Upcoming(Self.episode(2, of: Self.first), in: Self.first))
    }

    @Test("FR-CONTENT-02: the last episode of a season is followed by the first of the next season")
    func acrossTheSeasons() async throws {
        let order = EpisodeOrder(catalogue: StubCatalogue())

        let next = try await order.following(Self.episode(2, of: Self.first).id,
                                             at: Self.place(in: Self.first),
                                             in: .normal)

        #expect(next == Upcoming(Self.episode(1, of: Self.second), in: Self.second))
    }

    @Test("FR-CONTENT-02: the last episode of the last season is followed by nothing")
    func lastOfTheSeries() async throws {
        let order = EpisodeOrder(catalogue: StubCatalogue())

        let next = try await order.following(Self.episode(2, of: Self.second).id,
                                             at: Self.place(in: Self.second),
                                             in: .normal)

        #expect(next == nil)
    }

    @Test("FR-CONTENT-02: a season with nothing in it is passed over")
    func emptySeasonIsPassedOver() async throws {
        let empty = SeasonID(rawValue: "empty")
        let order = EpisodeOrder(catalogue: StubCatalogue(season: { season in
            season == empty ? [] : StubCatalogue.episodes(of: season)
        }))

        let next = try await order.following(Self.episode(2, of: Self.first).id,
                                             at: Self.place(in: Self.first, of: [Self.first, empty, Self.second]),
                                             in: .normal)

        #expect(next?.season == Self.second)
    }

    @Test("FR-CONTENT-02: when NPO cannot say what follows, that is not the same as nothing following")
    func unknownIsNotTheEnd() async {
        let unreachable = EpisodeOrder(catalogue: StubCatalogue(season: { _ in throw BackendError.unreachable }))
        let order = EpisodeOrder(catalogue: StubCatalogue())

        await #expect(throws: BackendError.unreachable) {
            try await unreachable.following(Self.episode(1, of: Self.first).id,
                                            at: Self.place(in: Self.first),
                                            in: .normal)
        }
        await #expect(throws: BackendError.itemUnavailable) {
            try await order.following(EpisodeID(rawValue: "gone"), at: Self.place(in: Self.first), in: .normal)
        }
    }
}
