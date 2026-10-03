//
//  SeriesDetailModel.swift
//  NPO light
//

import Foundation
import Observation

/// A series' detail page: the series, one season's episodes at a time, and the
/// episode being looked at (FR-CONTENT-07, FR-CONTENT-08).
@MainActor
@Observable
final class SeriesDetailModel {
    enum Page: Equatable {
        case loading
        case loaded(SeriesDetail)

        /// NPO no longer has the series (FR-CONTENT-05).
        case unavailable

        /// The series could not be fetched; trying again may help.
        case failed
    }

    enum Episodes: Equatable {
        case loading
        case loaded([Playable])
        case failed
    }

    /// What the list that led here already knew, shown while the rest loads.
    let summary: SeriesSummary
    let mode: Mode

    private(set) var page = Page.loading

    /// The season whose episodes are shown.
    private(set) var shownSeason: SeasonID?

    private(set) var episodes = Episodes.loading

    /// The fetch of the shown season's episodes, while it is under way.
    private(set) var pending: Task<Void, Never>?

    /// Seasons already fetched, so that moving back along the picker does not
    /// ask NPO again.
    private var fetched: [SeasonID: [Playable]] = [:]

    private var focused: EpisodeID?

    private let catalogue: any Catalogue

    init(summary: SeriesSummary, catalogue: any Catalogue, mode: Mode) {
        self.summary = summary
        self.catalogue = catalogue
        self.mode = mode
    }

    /// The seasons to pick from. A series with one season has no picker.
    var pickerSeasons: [Season] {
        guard case .loaded(let detail) = page, detail.seasons.count > 1 else { return [] }
        return detail.seasons
    }

    /// The episode previewed beside the list: the one that last had focus, or
    /// the first of the season while none of its episodes has had it.
    var previewed: Playable? {
        guard case .loaded(let list) = episodes else { return nil }
        return list.first { $0.id == focused } ?? list.first
    }

    /// Fetches the series and opens its first season.
    ///
    /// The page is meant to open on the season holding the next unwatched
    /// episode. Nothing records what was watched yet, so that is the first.
    func load() async {
        page = .loading
        do {
            let detail = try await catalogue.series(summary.id, in: mode)
            page = .loaded(detail)
            if let first = detail.seasons.first {
                show(first.id)
            } else {
                episodes = .loaded([])
            }
        } catch BackendError.itemUnavailable {
            page = .unavailable
        } catch is CancellationError {
            // The page went away.
        } catch {
            page = .failed
        }
    }

    /// Shows a season's episodes. Called as focus moves along the picker, with
    /// no further press.
    func show(_ season: SeasonID) {
        guard season != shownSeason || episodes == .failed else { return }
        pending?.cancel()
        shownSeason = season
        if let known = fetched[season] {
            pending = nil
            episodes = .loaded(known)
            return
        }
        episodes = .loading
        pending = Task {
            await self.fetch(season)
        }
    }

    /// The button on a season that failed to load.
    func retryEpisodes() {
        guard let shownSeason else { return }
        show(shownSeason)
    }

    /// An episode in the list took focus.
    func focus(_ episode: EpisodeID) {
        focused = episode
    }

    private func fetch(_ season: SeasonID) async {
        let outcome: Episodes
        do {
            let list = try await catalogue.episodes(of: season, in: mode)
            fetched[season] = list
            outcome = .loaded(list)
        } catch is CancellationError {
            return
        } catch {
            outcome = .failed
        }
        // Focus has moved on along the picker: this answer is for a season
        // that is no longer the one shown.
        guard !Task.isCancelled, shownSeason == season else { return }
        episodes = outcome
    }
}
