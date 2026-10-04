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

    private static func place(in season: SeasonID) -> SeriesPlace {
        SeriesPlace(series: StubCatalogue.results.series[0], season: season)
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
        let empty = Season(id: SeasonID(rawValue: "empty"), title: "Leeg")
        let detail = SeriesDetail(id: StubCatalogue.detail.id,
                                  title: "Freeks wilde wereld",
                                  synopsis: nil,
                                  artwork: nil,
                                  seasons: [StubCatalogue.seasons[0], empty, StubCatalogue.seasons[1]])
        let order = EpisodeOrder(catalogue: StubCatalogue(detail: { _ in detail }, season: { season in
            season == empty.id ? [] : StubCatalogue.episodes(of: season)
        }))

        let next = try await order.following(Self.episode(2, of: Self.first).id,
                                             at: Self.place(in: Self.first),
                                             in: .normal)

        #expect(next?.season == Self.second)
    }

    @Test("FR-CONTENT-02: in a series NPO lists latest season first, the next season is still the later one")
    func newestFirstIsFollowedForwards() async throws {
        var detail = StubCatalogue.detail
        detail.listsNewestFirst = true
        let order = EpisodeOrder(catalogue: StubCatalogue(detail: { [detail] _ in detail }))

        // Listed first, broadcast last: nothing follows its last episode.
        let afterTheLatest = try await order.following(Self.episode(2, of: Self.first).id,
                                                       at: Self.place(in: Self.first),
                                                       in: .normal)
        let afterTheEarlier = try await order.following(Self.episode(2, of: Self.second).id,
                                                        at: Self.place(in: Self.second),
                                                        in: .normal)

        #expect(afterTheLatest == nil)
        #expect(afterTheEarlier == Upcoming(Self.episode(1, of: Self.first), in: Self.first))
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

    @Test("FR-CONTENT-02, FR-PLAY-07: an episode NPO no longer has, or will not play, is passed over")
    func unavailableEpisodeIsSkipped() async throws {
        let three = (1...3).map { number in
            Playable(id: EpisodeID(rawValue: "episode-\(number)"), title: "Aflevering \(number)", caption: nil,
                     synopsis: nil, duration: nil, artwork: nil)
        }
        let gone = EpisodeOrder(catalogue: StubCatalogue(season: { _ in three }, programme: { id in
            if id == three[1].id { throw BackendError.itemUnavailable }
            return StubCatalogue.film(id)
        }))
        let refused = EpisodeOrder(catalogue: StubCatalogue(season: { _ in three }, programme: { id in
            ProgrammeDetail(playable: StubCatalogue.film(id).playable, isPlayable: id != three[1].id)
        }))

        #expect(try await gone.following(three[0].id, at: Self.place(in: Self.first), in: .normal)?.id == three[2].id)
        #expect(try await refused.following(three[0].id, at: Self.place(in: Self.first), in: .normal)?.id
                == three[2].id)
    }

    @Test("FR-PLAY-07: when every later episode is unavailable, nothing follows, also across seasons")
    func nothingPlayableFollows() async throws {
        let order = EpisodeOrder(catalogue: StubCatalogue(programme: { _ in throw BackendError.itemUnavailable }))

        let next = try await order.following(Self.episode(1, of: Self.first).id,
                                             at: Self.place(in: Self.first),
                                             in: .normal)

        #expect(next == nil)
    }

    @Test("NFR-REL-02: an episode NPO could not be asked about is not passed over")
    func unknownAvailabilityIsTried() async throws {
        let order = EpisodeOrder(catalogue: StubCatalogue(programme: { _ in throw BackendError.unreachable }))

        let next = try await order.following(Self.episode(1, of: Self.first).id,
                                             at: Self.place(in: Self.first),
                                             in: .normal)

        #expect(next?.id == Self.episode(2, of: Self.first).id)
    }
}
