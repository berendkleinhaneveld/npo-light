//
//  SharedPositions.swift
//  NPO light
//

import Foundation

/// Takes the positions NPO reports into the television's own store, which is
/// the one place every page reads them from (FR-PLAY-13, ADR 0028).
///
/// A position is taken when it is news: not the one NPO reported before.
/// NPO repeating itself changes nothing, so what the television wrote since
/// stands — a remembered page may be shown again, and a report that never
/// reached NPO does not cost the position it was about.
nonisolated struct SharedPositions: Sendable {
    let progress: any ProgressKeeping
    let clock: any Clocking

    /// Whether NPO said this about `id` before.
    func isKnown(_ position: SharedPosition, of id: EpisodeID, in mode: Mode) async -> Bool {
        position.isSame(as: await progress.progress(of: id, in: mode)?.shared)
    }

    /// - Returns: the ones that were news, and are the television's own now.
    @discardableResult
    func take(_ positions: [EpisodeID: SharedPosition], in mode: Mode) async -> Set<EpisodeID> {
        guard !positions.isEmpty else { return [] }
        let known = await progress.progress(of: Array(positions.keys), in: mode)
        var news: Set<EpisodeID> = []
        for (id, position) in positions where !position.isSame(as: known[id]?.shared) {
            guard position.offset.isFinite, position.offset > 0 else { continue }
            let before = known[id]
            let duration = position.duration ?? before?.duration
            // Past the threshold it is finished and has nothing to resume;
            // before it, what was finished stays finished (FR-PLAY-04).
            let isFinished = Completion.isFinished(at: position.offset, of: duration)
            let update = PlaybackProgress(id: id,
                                          offset: isFinished ? nil : position.offset,
                                          finishedAt: isFinished ? before?.finishedAt ?? clock.now : before?.finishedAt,
                                          updatedAt: clock.now,
                                          duration: duration,
                                          shared: position.offset)
            // NPO has it, so it need not be where tvOS cannot reach.
            guard (try? await progress.note(update, in: mode)) != nil else { continue }
            news.insert(id)
        }
        return news
    }

    /// The same, for the positions a list came with.
    @discardableResult
    func take(from playables: [Playable], in mode: Mode) async -> Set<EpisodeID> {
        let positions = playables.compactMap { playable in playable.position.map { (playable.id, $0) } }
        return await take(Dictionary(positions) { _, last in last }, in: mode)
    }
}

/// A catalogue that takes in the positions NPO's answers come with, on their
/// way to whoever asked (FR-PLAY-13). Nothing above it knows: a page reads
/// the store as it always did.
nonisolated struct PositionTakingCatalogue: Catalogue {
    private let wrapped: any Catalogue
    private let positions: SharedPositions

    init(wrapping wrapped: any Catalogue, positions: SharedPositions) {
        self.wrapped = wrapped
        self.positions = positions
    }

    func availableModes() async throws -> Set<Mode> {
        try await wrapped.availableModes()
    }

    func search(for query: String, in mode: Mode) async throws -> SearchResults {
        let results = try await wrapped.search(for: query, in: mode)
        await positions.take(from: results.singleProgrammes + results.episodes, in: mode)
        return results
    }

    func series(_ id: ItemID, in mode: Mode) async throws -> SeriesDetail {
        try await wrapped.series(id, in: mode)
    }

    func programme(_ id: EpisodeID, in mode: Mode) async throws -> ProgrammeDetail {
        let detail = try await wrapped.programme(id, in: mode)
        await positions.take(from: [detail.playable], in: mode)
        return detail
    }

    func episodes(of season: SeasonID, in mode: Mode) async throws -> [Playable] {
        let episodes = try await wrapped.episodes(of: season, in: mode)
        await positions.take(from: episodes, in: mode)
        return episodes
    }

    func place(of episode: EpisodeID, in mode: Mode) async throws -> SeriesPlace? {
        try await wrapped.place(of: episode, in: mode)
    }

    /// Left to ``ContinuedElsewhere``, which has to know what was news.
    func continuing(in mode: Mode) async throws -> [Continued] {
        try await wrapped.continuing(in: mode)
    }

    func discontinue(_ episode: EpisodeID, in mode: Mode) async throws {
        try await wrapped.discontinue(episode, in: mode)
    }

    func rememberedSeries(_ id: ItemID, in mode: Mode) async -> SeriesDetail? {
        await wrapped.rememberedSeries(id, in: mode)
    }

    func rememberedEpisodes(of season: SeasonID, in mode: Mode) async -> [Playable]? {
        await wrapped.rememberedEpisodes(of: season, in: mode)
    }

    func rememberedProgramme(_ id: EpisodeID, in mode: Mode) async -> ProgrammeDetail? {
        await wrapped.rememberedProgramme(id, in: mode)
    }
}
