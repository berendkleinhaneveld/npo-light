//
//  HomeModel.swift
//  NPO light
//

import Foundation
import Observation

/// Where the one navigation stack can go (ADR 0011).
enum Destination: Hashable {
    case search
    case series(SeriesSummary)
}

/// The home page's state: where the stack is, what is playing, and the rows.
///
/// Nothing tells it that a pin changed on another page. It reads again when
/// the home page comes back on screen and when the player closes, which is
/// the price ADR 0011 names for having no `@Query` (FR-HOME-10).
@MainActor
@Observable
final class HomeModel {
    var path: [Destination] = []

    /// What is playing. The player is presented over the stack rather than
    /// pushed onto it (ADR 0011).
    var playing: PlayRequest?

    /// Counts the playbacks that ended. A page that shows what was watched
    /// reads it again when this changes (FR-HOME-10).
    private(set) var playbacksEnded = 0

    /// The pinned series, most recently pinned first (FR-HOME-02), each as
    /// the episode it continues with (FR-HOME-04).
    private(set) var pinned: [HomeTile] = []

    /// The *Kijk verder* row (FR-HOME-06).
    private(set) var continuing: [HomeTile] = []

    let mode: Mode

    private let pins: any Pins
    private let watched: WatchedState
    private let clock: any Clocking

    init(pins: any Pins, watched: WatchedState, clock: any Clocking, mode: Mode) {
        self.pins = pins
        self.watched = watched
        self.clock = clock
        self.mode = mode
    }

    /// Reads the rows as they are kept now.
    func refresh() async {
        let series = await pins.pinned(in: mode)
        let entries = await watched.history.entries(in: mode)
        let row = ContinueWatching.row(from: entries, at: clock.now)
        // A pinned series keeps its tile when it has left the row
        // (FR-HOME-07), so its entry is looked for among all of them.
        let pinnedEntries = series.compactMap { pin in entries.first { $0.id == pin.id } }
        let continued = (row + pinnedEntries).compactMap(\.next?.id)
        let positions = await watched.progress.progress(of: continued, in: mode)
        pinned = series.map { pin in
            guard let entry = entries.first(where: { $0.id == pin.id }), entry.kind == .series else {
                return HomeTile(pinned: pin)
            }
            return HomeTile(entry, positions: positions)
        }
        continuing = row.map { HomeTile($0, positions: positions) }
    }

    /// Takes a series off the pinned row, from the row itself (FR-HOME-05).
    func unpin(_ id: ItemID) async {
        // A pin that could not be removed is still shown, as it is kept.
        try? await pins.unpin(id, in: mode)
        await refresh()
    }

    /// Takes an item off the *Kijk verder* row, and leaves where it was
    /// watched to alone (FR-HOME-08).
    func remove(_ id: ItemID) async {
        try? await watched.history.hide(id, in: mode)
        await refresh()
    }

    /// A tile was selected: it plays what it continues with, or opens the
    /// series' page when there is nothing to play (FR-HOME-04, FR-HOME-07).
    func select(_ tile: HomeTile) {
        if let request = tile.request {
            play(request)
        } else if let series = tile.series {
            open(series)
        }
    }

    func openSearch() {
        path.append(.search)
    }

    func open(_ series: SeriesSummary) {
        path.append(.series(series))
    }

    /// Something was chosen from search results.
    func open(_ pick: SearchPick) {
        switch pick {
        case .series(let series):
            open(series)
        case .single(let playable):
            // Straight to playing: a single programme's own page has no
            // endpoint yet (Q-10).
            play(PlayRequest(playable: playable, origin: .single))
        case .playable(let playable):
            play(playable)
        }
    }

    func play(_ playable: Playable) {
        play(PlayRequest(playable: playable))
    }

    func play(_ request: PlayRequest) {
        playing = request
    }

    /// The player closed, and where it stopped has been written down: the
    /// rows are read again (FR-HOME-10).
    func playbackEnded() async {
        playbacksEnded += 1
        await refresh()
    }
}
