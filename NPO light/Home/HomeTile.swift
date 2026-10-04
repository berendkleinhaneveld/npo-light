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

    /// A pinned series nobody started.
    init(pinned series: SeriesSummary) {
        id = series.id
        kind = .series
        title = series.title
        artwork = series.artwork
        itemArtwork = series.artwork
        state = .notStarted
        origin = .unknown
        self.series = series
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
        guard case .continues(let next, _) = state else { return nil }
        return PlayRequest(playable: next.playable, origin: origin)
    }

    /// What the tile plays, as the watch later list keeps it.
    var saving: SavedItem? {
        guard case .continues(let next, _) = state else { return nil }
        return SavedItem(next.playable, origin: origin)
    }
}
