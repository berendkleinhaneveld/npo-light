//
//  CachedCatalogue.swift
//  NPO light
//

import Foundation

/// A catalogue that keeps what NPO answered about a series, a season and a
/// programme, and answers from that while it is young (FR-CONTENT-04,
/// ADR 0024).
///
/// - A young answer is given without asking NPO.
/// - An old one is asked for again. When NPO cannot be reached, the old
///   answer is given after all: something seen before can be looked at
///   without a network (NFR-REL-01).
/// - Whatever is kept, however old, is there to show at once while NPO is
///   asked: the `remembered…` questions.
///
/// Search is not kept: its answer is for what was typed a moment ago. Neither
/// is where an episode sits in its series, nor which modes the account has.
nonisolated struct CachedCatalogue: Catalogue {
    /// How long an answer is given without asking again. A new episode shows
    /// up at most this long after NPO lists it.
    static let maximumAge: TimeInterval = 30 * 60

    private let wrapped: any Catalogue
    private let cache: CatalogueCache
    private let clock: any Clocking

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
        try await answer(for: Self.key(series: id, mode)) {
            try await wrapped.series(id, in: mode)
        }
    }

    func episodes(of season: SeasonID, in mode: Mode) async throws -> [Playable] {
        try await answer(for: Self.key(season: season, mode)) {
            try await wrapped.episodes(of: season, in: mode)
        }
    }

    func programme(_ id: EpisodeID, in mode: Mode) async throws -> ProgrammeDetail {
        try await answer(for: Self.key(programme: id, mode)) {
            try await wrapped.programme(id, in: mode)
        }
    }

    func rememberedSeries(_ id: ItemID, in mode: Mode) async -> SeriesDetail? {
        await cache.entry(SeriesDetail.self, for: Self.key(series: id, mode))?.value
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

    // MARK: The rule

    private func answer<Value: Codable & Sendable>(
        for key: CatalogueCache.Key,
        asking fetch: () async throws -> Value
    ) async throws -> Value {
        let kept = await cache.entry(Value.self, for: key)
        if let kept, clock.now.timeIntervalSince(kept.fetchedAt) < Self.maximumAge {
            return kept.value
        }
        do {
            let fresh = try await fetch()
            await cache.store(fresh, for: key, at: clock.now)
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
