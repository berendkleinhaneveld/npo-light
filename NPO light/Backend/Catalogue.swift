//
//  Catalogue.swift
//  NPO light
//

import Foundation

/// What NPO has to watch, in the app's own types (ADR 0008).
///
/// Every method takes the mode, and nothing reads an ambient one: which
/// catalogue is being asked is visible at the call (ADR 0011, FR-MODE-04).
nonisolated protocol Catalogue: Sendable {
    /// The modes this account can use. Normal mode always; kids mode only when
    /// the account has an NPO kids profile to browse as (ADR 0014).
    func availableModes() async throws -> Set<Mode>

    /// Series and playable items matching `query`, from the mode's catalogue.
    func search(for query: String, in mode: Mode) async throws -> SearchResults

    /// A series with its seasons as NPO lists them, and which way that runs.
    ///
    /// Throws ``BackendError/itemUnavailable`` when NPO no longer has it.
    func series(_ id: ItemID, in mode: Mode) async throws -> SeriesDetail

    /// A single programme as its own page describes it.
    ///
    /// Throws ``BackendError/itemUnavailable`` when NPO no longer has it.
    func programme(_ id: EpisodeID, in mode: Mode) async throws -> ProgrammeDetail

    /// The episodes of one season, in broadcast order.
    func episodes(of season: SeasonID, in mode: Mode) async throws -> [Playable]

    /// Where `episode` sits in its series, or `nil` for a programme that
    /// belongs to none. A list does not say (Q-10); NPO's answer to playing
    /// the episode does.
    func place(of episode: EpisodeID, in mode: Mode) async throws -> SeriesPlace?

    // MARK: What is remembered

    /// A series as an earlier answer described it, however long ago, without
    /// asking NPO: what a page shows at once while it asks again
    /// (FR-CONTENT-04). `nil` when nothing is remembered.
    func rememberedSeries(_ id: ItemID, in mode: Mode) async -> SeriesDetail?

    /// A season's episodes as an earlier answer listed them.
    func rememberedEpisodes(of season: SeasonID, in mode: Mode) async -> [Playable]?

    /// A single programme as an earlier answer described it.
    func rememberedProgramme(_ id: EpisodeID, in mode: Mode) async -> ProgrammeDetail?
}

/// A catalogue that remembers nothing: NPO's own, and the ones that stand in
/// for it. The cache is what remembers (ADR 0024).
nonisolated extension Catalogue {
    func rememberedSeries(_ id: ItemID, in mode: Mode) async -> SeriesDetail? { nil }

    func rememberedEpisodes(of season: SeasonID, in mode: Mode) async -> [Playable]? { nil }

    func rememberedProgramme(_ id: EpisodeID, in mode: Mode) async -> ProgrammeDetail? { nil }
}
