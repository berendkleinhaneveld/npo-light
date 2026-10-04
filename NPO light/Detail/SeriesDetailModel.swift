//
//  SeriesDetailModel.swift
//  NPO light
//

import Foundation
import Observation

/// A series' detail page: the series, one season's episodes at a time, the
/// episode being looked at, and what was watched of it (FR-CONTENT-03,
/// FR-CONTENT-07, FR-CONTENT-08).
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

    /// How far an episode was watched, as a list shows it.
    enum Watched: Equatable {
        case notStarted
        case started
        case finished
    }

    /// What the page's main action plays (FR-CONTENT-03).
    struct Primary: Equatable {
        let episode: Playable
        let season: SeasonID

        /// It has a position to carry on from: the action reads
        /// *Verder kijken* rather than *Afspelen*.
        let resumes: Bool
    }

    /// What the list that led here already knew, shown while the rest loads.
    let summary: SeriesSummary
    let mode: Mode

    private(set) var page = Page.loading

    /// Whether the series is pinned in this mode (FR-HOME-03).
    private(set) var isPinned = false

    /// The season whose episodes are shown.
    private(set) var shownSeason: SeasonID?

    private(set) var episodes = Episodes.loading

    /// The fetch of the shown season's episodes, while it is under way.
    private(set) var pending: Task<Void, Never>?

    /// Seasons already fetched, so that moving back along the picker does not
    /// ask NPO again.
    private var fetched: [SeasonID: [Playable]] = [:]

    private var focused: EpisodeID?

    /// The episode the series continues with, once one was played.
    private var upNext: Upcoming?

    /// Every episode of the series was watched (FR-HOME-04).
    private var hasNothingNext = false

    /// The positions of the episodes on this page that have one.
    private var positions: [EpisodeID: PlaybackProgress] = [:]

    private let catalogue: any Catalogue
    private let pins: any Pins
    private let watched: WatchedState

    init(summary: SeriesSummary, catalogue: any Catalogue, pins: any Pins, watched: WatchedState, mode: Mode) {
        self.summary = summary
        self.catalogue = catalogue
        self.pins = pins
        self.watched = watched
        self.mode = mode
    }

    /// Every episode was watched, and there is nothing to offer
    /// (FR-HOME-04).
    var isFullyWatched: Bool {
        hasNothingNext && primary == nil
    }

    /// The episode the main action plays: the one the series continues with,
    /// or, while it continues with none, where such a series is started.
    /// Nothing for a series that was watched to its end: an episode is
    /// played again from the list.
    var primary: Primary? {
        guard case .loaded(let detail) = page else { return nil }
        let seasons = detail.seasons
        if let upNext, let season = upNext.season, seasons.contains(where: { $0.id == season }) {
            // The list's own episode when it is on the page: it has the
            // description the kept one lacks.
            let listed = fetched[season]?.first { $0.id == upNext.id }
            return Primary(episode: listed ?? upNext.playable,
                           season: season,
                           resumes: positions[upNext.id]?.offset != nil)
        }
        guard let first = seasons.first, let listed = fetched[first.id] else { return nil }
        // A programme NPO lists latest first is followed as it is broadcast:
        // it starts with its latest episode, as in NPO's own app, and offers
        // that one again whenever a newer one than was watched has come.
        if detail.listsNewestFirst {
            guard let latest = listed.last, positions[latest.id]?.isFinished != true else { return nil }
            return Primary(episode: latest, season: first.id, resumes: positions[latest.id]?.offset != nil)
        }
        guard !hasNothingNext, let episode = listed.first else { return nil }
        return Primary(episode: episode, season: first.id, resumes: positions[episode.id]?.offset != nil)
    }

    func watched(_ episode: EpisodeID) -> Watched {
        guard let position = positions[episode] else { return .notStarted }
        // Watched stays watched while it is watched again (FR-PLAY-02).
        if position.isFinished { return .finished }
        return position.offset == nil ? .notStarted : .started
    }

    /// What playing `episode` needs: the episode, and where in the series it
    /// is, so that the series can move on when it is finished (FR-PLAY-09).
    /// `season` is the one being shown unless another is named.
    func request(for episode: Playable, in season: SeasonID? = nil) -> PlayRequest {
        guard loadedSeasons != nil, let season = season ?? shownSeason else {
            return PlayRequest(playable: episode)
        }
        return PlayRequest(playable: episode, origin: .series(SeriesPlace(series: current, season: season)))
    }

    private var loadedSeasons: [Season]? {
        guard case .loaded(let detail) = page else { return nil }
        return detail.seasons
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

    /// Fetches the series and opens the season that holds the episode the
    /// main action plays: the first, for a series nobody started or one
    /// watched to its end (FR-CONTENT-07).
    func load() async {
        page = .loading
        isPinned = await pins.isPinned(summary.id, in: mode)
        do {
            let detail = try await catalogue.series(summary.id, in: mode)
            await readWatched()
            page = .loaded(detail)
            let continued = detail.seasons.first { $0.id == upNext?.season }
            if let opening = continued ?? detail.seasons.first {
                show(opening.id)
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

    /// Reads what was watched of the series as it is kept now: when the page
    /// opens, and again when the player closes (FR-HOME-10).
    func readWatched() async {
        let entry = await watched.history.entry(for: summary.id, in: mode)
        upNext = entry?.next
        hasNothingNext = entry.map { $0.next == nil } ?? false
        let listed = fetched.values.flatMap { $0.map(\.id) }
        positions = await watched.progress.progress(of: listed + [upNext?.id].compactMap(\.self), in: mode)
    }

    /// Pins the series, or takes its pin away (FR-HOME-03, FR-HOME-05).
    ///
    /// What is pinned is the series as NPO now describes it, when the page
    /// has it: the pin's own title and image are what its tile is drawn from.
    func togglePin() async {
        do {
            if isPinned {
                try await pins.unpin(summary.id, in: mode)
            } else {
                try await pins.pin(current, in: mode)
            }
        } catch {
            // Nothing was written; what is shown stays what is kept.
        }
        isPinned = await pins.isPinned(summary.id, in: mode)
    }

    private var current: SeriesSummary {
        guard case .loaded(let detail) = page else { return summary }
        return SeriesSummary(id: summary.id, title: detail.title, artwork: detail.artwork ?? summary.artwork)
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

    /// Focus reached `season` in the picker, from `previous` — `nil` when it
    /// came from outside the picker. Answers the season that is to have focus.
    ///
    /// Moving along the picker shows the season focus is on. Arriving from the
    /// episodes or the header does not: the focus engine lands on whichever
    /// season is nearest, and that one would replace the list the user just
    /// left. Focus goes to the season being shown instead (FR-CONTENT-07).
    func pickerFocusMoved(to season: SeasonID, from previous: SeasonID?) -> SeasonID {
        if previous == nil, let shownSeason, shownSeason != season {
            return shownSeason
        }
        show(season)
        return season
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
            let known = await watched.progress.progress(of: list.map(\.id), in: mode)
            positions.merge(known) { _, read in read }
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
