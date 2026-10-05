//
//  CachedCatalogue.swift
//  NPO light
//

import Foundation
import Synchronization

/// A catalogue that keeps what NPO answered about a series, a season and a
/// programme, and answers from that while it is young (FR-CONTENT-04,
/// ADR 0024).
///
/// - A young answer is given without asking NPO. How long an answer is young
///   depends on what it is about: half an hour for a programme followed as
///   it is broadcast, a day for the latest season of any other series, a
///   week for what no longer changes.
/// - An old one is asked for again. When NPO cannot be reached, the old
///   answer is given after all: something seen before can be looked at
///   without a network (NFR-REL-01).
/// - Whatever is kept, however old, is there to show at once while NPO is
///   asked: the `remembered…` questions.
///
/// Search is not kept: its answer is for what was typed a moment ago. Neither
/// is where an episode sits in its series, nor which modes the account has.
nonisolated final class CachedCatalogue: Catalogue {
    typealias Pace = CatalogueCache.Pace

    private let wrapped: any Catalogue
    private let cache: CatalogueCache
    private let clock: any Clocking

    /// The pace of each season whose series passed through here, by the
    /// season's key: a season's own list does not say what it is a season
    /// of.
    private let seasons = Mutex<[CatalogueCache.Key: Pace]>([:])

    init(wrapping wrapped: any Catalogue, cache: CatalogueCache, clock: any Clocking) {
        self.wrapped = wrapped
        self.cache = cache
        self.clock = clock
    }

    func availableModes() async throws -> Set<Mode> {
        try await wrapped.availableModes()
    }

    func search(for query: String, in mode: Mode) async throws -> SearchResults {
        try await wrapped.search(for: query, in: mode)
    }

    func place(of episode: EpisodeID, in mode: Mode) async throws -> SeriesPlace? {
        try await wrapped.place(of: episode, in: mode)
    }

    func series(_ id: ItemID, in mode: Mode) async throws -> SeriesDetail {
        let detail = try await answer(for: Self.key(series: id, mode), pace: { Self.pace(of: $0) }, asking: {
            try await wrapped.series(id, in: mode)
        })
        note(detail, in: mode)
        return detail
    }

    func episodes(of season: SeasonID, in mode: Mode) async throws -> [Playable] {
        let key = Self.key(season: season, mode)
        let known = seasons.withLock { $0[key] }
        return try await answer(for: key, pace: { _ in known }, asking: {
            try await wrapped.episodes(of: season, in: mode)
        })
    }

    /// A programme's page says what it is, which does not change. Whether it
    /// can still be played does; the player is what finds that out.
    func programme(_ id: EpisodeID, in mode: Mode) async throws -> ProgrammeDetail {
        try await answer(for: Self.key(programme: id, mode), pace: { _ in .settled }, asking: {
            try await wrapped.programme(id, in: mode)
        })
    }

    func rememberedSeries(_ id: ItemID, in mode: Mode) async -> SeriesDetail? {
        let detail = await cache.entry(SeriesDetail.self, for: Self.key(series: id, mode))?.value
        if let detail { note(detail, in: mode) }
        return detail
    }

    func rememberedEpisodes(of season: SeasonID, in mode: Mode) async -> [Playable]? {
        await cache.entry([Playable].self, for: Self.key(season: season, mode))?.value
    }

    func rememberedProgramme(_ id: EpisodeID, in mode: Mode) async -> ProgrammeDetail? {
        await cache.entry(ProgrammeDetail.self, for: Self.key(programme: id, mode))?.value
    }

    // MARK: Keys

    private static func key(series id: ItemID, _ mode: Mode) -> CatalogueCache.Key {
        CatalogueCache.Key(kind: .series, identifier: id.rawValue, mode: mode)
    }

    private static func key(season id: SeasonID, _ mode: Mode) -> CatalogueCache.Key {
        CatalogueCache.Key(kind: .episodes, identifier: id.rawValue, mode: mode)
    }

    private static func key(programme id: EpisodeID, _ mode: Mode) -> CatalogueCache.Key {
        CatalogueCache.Key(kind: .programme, identifier: id.rawValue, mode: mode)
    }

    // MARK: Pace

    /// NPO says which programmes are followed as they are broadcast: it
    /// lists those latest first.
    private static func pace(of series: SeriesDetail) -> Pace {
        series.listsNewestFirst ? .current : .running
    }

    /// Remembers how fast each season of `series` changes: the latest one as
    /// fast as the series, the earlier ones not at all.
    private func note(_ series: SeriesDetail, in mode: Mode) {
        let latest = series.broadcastOrder.last
        seasons.withLock { known in
            for season in series.seasons {
                known[Self.key(season: season.id, mode)] = season.id == latest ? Self.pace(of: series) : .settled
            }
        }
    }

    // MARK: The rule

    /// - Parameter pace: how fast `value` changes, when that is known here.
    ///   When it is not, the pace the answer was kept with is used, and for
    ///   an answer never kept the fastest.
    private func answer<Value: Codable & Sendable>(
        for key: CatalogueCache.Key,
        pace: (Value) -> Pace?,
        asking fetch: () async throws -> Value
    ) async throws -> Value {
        let kept = await cache.entry(Value.self, for: key)
        if let kept {
            let age = (pace(kept.value) ?? kept.pace ?? .current).age
            if clock.now.timeIntervalSince(kept.fetchedAt) < age { return kept.value }
        }
        do {
            let fresh = try await fetch()
            await cache.store(fresh, for: key, at: clock.now, pace: pace(fresh) ?? kept?.pace ?? .current)
            return fresh
        } catch BackendError.itemUnavailable {
            // NPO no longer has it: what was kept is no longer true.
            await cache.remove(key)
            throw BackendError.itemUnavailable
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // NPO could not be asked. What was seen before is still worth
            // showing; with nothing kept, the failure is the answer.
            guard let kept else { throw error }
            return kept.value
        }
    }
}
