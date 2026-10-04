//
//  WatchedTypes.swift
//  NPO light
//

import Foundation

/// Where an episode sits in its series, as far as whoever starts it knows:
/// what is needed to say which episode follows it (FR-CONTENT-02).
///
/// A list does not name the series an episode belongs to (Q-10), so only the
/// series' own page can hand one over.
nonisolated struct SeriesPlace: Sendable, Equatable {
    let series: SeriesSummary

    /// Every season of the series, from the first to the latest: not always
    /// the order NPO lists them in.
    let seasons: [SeasonID]

    /// The season the episode is in.
    let season: SeasonID
}

/// Something to play, and where in its series it is when that is known.
nonisolated struct PlayRequest: Sendable, Equatable, Identifiable {
    let playable: Playable
    var place: SeriesPlace?

    var id: EpisodeID { playable.id }
}

/// The episode a series continues with, as it is kept: enough to name it on
/// a tile and to play it without asking NPO first (ADR 0015).
nonisolated struct Upcoming: Sendable, Equatable, Codable {
    let id: EpisodeID
    let title: String
    let caption: String?
    let artwork: URL?
    let season: SeasonID

    init(_ playable: Playable, in season: SeasonID) {
        id = playable.id
        title = playable.title
        caption = playable.caption
        artwork = playable.artwork
        self.season = season
    }

    /// What playing it needs. The description was not kept.
    var playable: Playable {
        Playable(id: id, title: title, caption: caption, synopsis: nil, duration: nil, artwork: artwork)
    }
}

/// What is kept about a series somebody started: which episode it continues
/// with (ADR 0012's `RecentlyWatchedEntry`, FR-PLAY-09).
///
/// The series is kept as a tile needs it, so that the entry can be drawn when
/// NPO no longer has the series (FR-CONTENT-05).
nonisolated struct WatchedEntry: Sendable, Equatable, Codable, Identifiable {
    let series: SeriesSummary

    /// The episode to continue with: the one being watched, or the one after
    /// it once that is finished. `nil` when nothing is left to watch.
    var next: Upcoming?

    /// When the last episode was finished. Absent while something is left.
    var finishedAt: Date?

    /// Taken off the row by hand, and nothing else (FR-HOME-08).
    var isHidden = false

    var playedAt: Date

    var id: ItemID { series.id }
}

/// One mode's entries, most recently played first, and the rules for the
/// list: a series has one entry, however many of its episodes were played
/// (FR-PLAY-09).
nonisolated struct WatchedList: Sendable, Equatable, Codable {
    private(set) var entries: [WatchedEntry] = []

    func entry(for id: ItemID) -> WatchedEntry? {
        entries.first { $0.id == id }
    }

    /// Puts `entry` at the front, in place of what was kept for its series.
    mutating func record(_ entry: WatchedEntry) {
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
    }
}
