//
//  HomeTile.swift
//  NPO light
//

import Foundation

/// The rules of the *Kijk verder* row (FR-HOME-06, FR-HOME-07). The row is
/// not kept: it is worked out from the entries each time it is shown, so
/// that nothing has to run while the app is closed (ADR 0006).
nonisolated enum ContinueWatching {
    /// How many items the row holds, per mode.
    static let cap = 20

    /// How long an item with nothing left to watch stays on the row.
    static let finishedStays: TimeInterval = 7 * 24 * 60 * 60

    /// The row at `now`: what was not taken off by hand and was not finished
    /// longer ago than ``finishedStays``, most recently played first, and no
    /// more than ``cap``.
    static func row(from entries: [WatchedEntry], at now: Date) -> [WatchedEntry] {
        let shown = entries.filter { entry in
            guard !entry.isHidden else { return false }
            // A finish in the future — a clock that was moved back — counts
            // as finished now.
            guard let finishedAt = entry.finishedAt else { return true }
            return now.timeIntervalSince(finishedAt) < finishedStays
        }
        return Array(shown.sorted { $0.playedAt > $1.playedAt }.prefix(cap))
    }
}

/// An item on the home page, and what selecting it does: a pinned series
/// or something on the *Kijk verder* row (FR-HOME-04, FR-HOME-06).
nonisolated struct HomeTile: Sendable, Equatable, Identifiable {
    enum State: Equatable {
        /// Nothing of it was played: selecting it opens its page.
        case notStarted

        /// It continues with an episode, this far in — nothing, for one
        /// that was not started, or whose length is not known.
        case continues(Upcoming, fraction: Double?)

        /// Nothing is left to watch (FR-HOME-07).
        case finished
    }

    let id: ItemID
    let kind: WatchedEntry.Kind
    let title: String
    /// The image the tile shows.
    let artwork: URL?

    /// The item's own image, which is not always the one shown.
    let itemArtwork: URL?
    let state: State

    /// What playing the tile needs to be told about what it plays.
    let origin: PlayOrigin

    /// The series whose page the tile can open, when it is of one.
    let series: SeriesSummary?

    /// Selecting it showed that NPO no longer has what it would play: the
    /// tile says so, keeps its place, and can still be taken off its row
    /// (FR-CONTENT-05, FR-LATER-11).
    var isUnavailable = false

    /// A pinned series nobody started. With the episode it starts with, the
    /// tile names and plays that one; without, it opens the series' page
    /// (FR-HOME-04).
    init(pinned series: SeriesSummary, startingWith start: Upcoming? = nil) {
        id = series.id
        kind = .series
        title = series.title
        itemArtwork = series.artwork
        self.series = series
        if let start, let season = start.season {
            artwork = start.artwork ?? series.artwork
            state = .continues(start, fraction: nil)
            origin = .series(SeriesPlace(series: series, season: season))
        } else {
            artwork = series.artwork
            state = .notStarted
            origin = .unknown
        }
    }

    /// Something saved for later: the tile is that exact thing, never the
    /// episode after it (FR-LATER-12).
    init(_ saved: SavedItem, positions: [EpisodeID: PlaybackProgress]) {
        id = ItemID(rawValue: saved.id.rawValue)
        kind = saved.isSingle ? .single : .series
        title = saved.series?.title ?? saved.episode.title
        artwork = saved.episode.artwork ?? saved.series?.artwork
        itemArtwork = saved.series?.artwork
        state = .continues(saved.episode, fraction: positions[saved.id]?.fraction)
        origin = saved.origin
        series = saved.series
    }

    /// An item somebody started. `positions` holds the position of what it
    /// continues with, when there is one.
    init(_ entry: WatchedEntry, positions: [EpisodeID: PlaybackProgress]) {
        id = entry.id
        kind = entry.kind
        title = entry.title
        origin = entry.origin
        itemArtwork = entry.artwork
        series = entry.kind == .series ? entry.series : nil
        if let next = entry.next {
            // The episode's own image: it is the episode that will play.
            artwork = next.artwork ?? entry.artwork
            state = .continues(next, fraction: positions[next.id]?.fraction)
        } else {
            artwork = entry.artwork
            state = .finished
        }
    }

    /// What selecting the tile plays, or `nil` when it opens a page instead:
    /// a finished item is not replayed silently (FR-HOME-07).
    var request: PlayRequest? {
        guard !isUnavailable, case .continues(let next, _) = state else { return nil }
        return PlayRequest(playable: next.playable, origin: origin)
    }

    /// What the tile stands or falls with: the episode it would play, or the
    /// series when it plays none.
    var subject: Subject {
        if case .continues(let next, _) = state { return .playable(next.id) }
        return kind == .series ? .series(id) : .playable(EpisodeID(rawValue: id.rawValue))
    }

    enum Subject: Hashable, Sendable {
        case playable(EpisodeID)
        case series(ItemID)
    }

    /// The item's own page: the series', or the single programme's.
    var page: Destination? {
        if let series { return .series(series) }
        guard kind == .single else { return nil }
        if case .continues(let programme, _) = state { return .programme(programme.playable) }
        // Finished: what is left of it is what the entry kept.
        return .programme(Playable(id: EpisodeID(rawValue: id.rawValue),
                                   title: title,
                                   caption: nil,
                                   synopsis: nil,
                                   duration: nil,
                                   artwork: itemArtwork))
    }

    /// What the tile plays, as the watch later list keeps it.
    var saving: SavedItem? {
        guard case .continues(let next, _) = state else { return nil }
        return SavedItem(next.playable, origin: origin)
    }
}
