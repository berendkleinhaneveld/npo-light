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

    /// The season the episode is in.
    let season: SeasonID
}

/// What is known about something that is played, by whoever starts it.
nonisolated enum PlayOrigin: Sendable, Equatable {
    /// An episode, and where in its series it is.
    case series(SeriesPlace)

    /// A programme that belongs to no series (FR-CONTENT-01).
    case single

    /// An episode of a series that was not named (Q-10).
    case unknown
}

/// Something to play, and what is known about it.
nonisolated struct PlayRequest: Sendable, Equatable, Identifiable {
    let playable: Playable
    var origin = PlayOrigin.unknown

    var id: EpisodeID { playable.id }
}

/// The episode a series continues with, as it is kept: enough to name it on
/// a tile and to play it without asking NPO first (ADR 0015).
nonisolated struct Upcoming: Sendable, Equatable, Codable {
    let id: EpisodeID
    let title: String
    let caption: String?
    let artwork: URL?

    /// The season it is in. A single programme has none.
    let season: SeasonID?

    init(_ playable: Playable, in season: SeasonID?) {
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

/// What is kept about an item somebody started — a series or a single
/// programme: what it continues with (ADR 0012's `RecentlyWatchedEntry`,
/// FR-PLAY-09).
///
/// The item is kept as a tile needs it, so that the entry can be drawn when
/// NPO no longer has it (FR-CONTENT-05).
nonisolated struct WatchedEntry: Sendable, Equatable, Codable, Identifiable {
    enum Kind: String, Sendable, Codable {
        case series
        case single
    }

    let id: ItemID
    let kind: Kind
    var title: String
    var artwork: URL?

    /// What to continue with: the episode being watched, or the one after it
    /// once that is finished; for a single programme, the programme. `nil`
    /// when nothing is left to watch.
    var next: Upcoming?

    /// When the last episode was finished. Absent while something is left.
    var finishedAt: Date?

    /// Taken off the row by hand, and nothing else (FR-HOME-08).
    var isHidden = false

    var playedAt: Date

    /// A series, continuing with `next`.
    init(series: SeriesSummary, next: Upcoming?, playedAt: Date) {
        id = series.id
        kind = .series
        title = series.title
        artwork = series.artwork
        self.next = next
        self.playedAt = playedAt
    }

    /// A single programme: an item of its own, under its own identifier.
    init(single playable: Playable, playedAt: Date) {
        id = ItemID(rawValue: playable.id.rawValue)
        kind = .single
        title = playable.title
        artwork = playable.artwork
        next = Upcoming(playable, in: nil)
        self.playedAt = playedAt
    }

    /// The series as a list shows it. Only meaningful for a series.
    var series: SeriesSummary {
        SeriesSummary(id: id, title: title, artwork: artwork)
    }

    /// What playing ``next`` needs to be told.
    var origin: PlayOrigin {
        guard kind == .series, let season = next?.season else { return kind == .single ? .single : .unknown }
        return .series(SeriesPlace(series: series, season: season))
    }
}

/// One mode's entries, most recently played first, and the rules for the
/// list: a series has one entry, however many of its episodes were played
/// (FR-PLAY-09).
nonisolated struct WatchedList: Sendable, Equatable, Codable {
    private(set) var entries: [WatchedEntry] = []

    func entry(for id: ItemID) -> WatchedEntry? {
        entries.first { $0.id == id }
    }

    /// Puts `entry` at the front, in place of what was kept for its item.
    mutating func record(_ entry: WatchedEntry) {
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
    }

    /// Marks the entry for `id` as taken off the row, where it is.
    mutating func hide(_ id: ItemID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isHidden = true
    }
}
