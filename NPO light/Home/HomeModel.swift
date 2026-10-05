//
//  HomeModel.swift
//  NPO light
//

import Foundation
import Observation

/// Where the one navigation stack can go (ADR 0011).
enum Destination: Hashable {
    case search
    case settings
    case programme(Playable)
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

    /// What was saved for later, most recently saved first (FR-LATER-04).
    private(set) var later: [HomeTile] = []

    /// What is on the watch later list, for an action that says whether it
    /// saves or removes (FR-LATER-03).
    private(set) var saved: Set<EpisodeID> = []

    let mode: Mode

    /// What selecting a tile showed NPO no longer has. Found out by trying,
    /// and remembered for as long as this home page lives: the app does not
    /// ask NPO about tiles nobody selected (ADR 0023).
    private var gone: Set<HomeTile.Subject> = []

    /// The episodes among them, for a series' page to mark in its list
    /// (FR-CONTENT-02).
    var unavailableEpisodes: Set<EpisodeID> {
        Set(gone.compactMap { subject in
            guard case .playable(let id) = subject else { return nil }
            return id
        })
    }

    private let pins: any Pins
    private let watched: WatchedState
    private let catalogue: any Catalogue
    private let clock: any Clocking

    init(pins: any Pins, watched: WatchedState, catalogue: any Catalogue, clock: any Clocking, mode: Mode) {
        self.pins = pins
        self.watched = watched
        self.catalogue = catalogue
        self.clock = clock
        self.mode = mode
    }

    /// Reads the rows as they are kept now.
    func refresh() async {
        let series = await pins.pinned(in: mode)
        let starts = await pins.starts(in: mode)
        let entries = await watched.history.entries(in: mode)
        let row = ContinueWatching.row(from: entries, at: clock.now)
        // A pinned series keeps its tile when it has left the row
        // (FR-HOME-07), so its entry is looked for among all of them.
        let pinnedEntries = series.compactMap { pin in entries.first { $0.id == pin.id } }
        let kept = await watched.later.saved(in: mode)
        let continued = (row + pinnedEntries).compactMap(\.next?.id) + kept.map(\.id)
        let positions = await watched.progress.progress(of: continued, in: mode)
        pinned = series.map { pin in
            guard let entry = entries.first(where: { $0.id == pin.id }), entry.kind == .series else {
                return HomeTile(pinned: pin, startingWith: starts[pin.id])
            }
            return HomeTile(entry, positions: positions)
        }
        continuing = row.map { HomeTile($0, positions: positions) }
        later = kept.map { HomeTile($0, positions: positions) }
        saved = Set(kept.map(\.id))
        mark()
    }

    /// Puts what is known about availability on the tiles.
    private func mark() {
        func marked(_ tiles: [HomeTile]) -> [HomeTile] {
            tiles.map { tile in
                var tile = tile
                tile.isUnavailable = gone.contains(tile.subject)
                return tile
            }
        }
        pinned = marked(pinned)
        continuing = marked(continuing)
        later = marked(later)
    }

    /// Saves something for later, or takes it off the list when it is on it
    /// (FR-LATER-03). `origin` is what is known about it where it is shown.
    func toggleSave(_ playable: Playable, origin: PlayOrigin) async {
        await toggleSave(SavedItem(playable, origin: origin))
    }

    /// The same, for what a tile plays.
    func toggleSave(_ tile: HomeTile) async {
        guard let item = tile.saving else { return }
        await toggleSave(item)
    }

    private func toggleSave(_ item: SavedItem) async {
        // A list that could not be written is shown as it is kept.
        if saved.contains(item.id) {
            try? await watched.later.remove(item.id, in: mode)
        } else {
            try? await watched.later.save(item, in: mode)
        }
        await refresh()
    }

    /// Takes a tile off the watch later row, by hand (FR-LATER-09).
    func removeSaved(_ tile: HomeTile) async {
        guard let item = tile.saving else { return }
        try? await watched.later.remove(item.id, in: mode)
        await refresh()
    }

    /// Opens the series an episode belongs to, which a list does not name:
    /// NPO is asked (Q-10). An episode it cannot place opens nothing.
    func openSeries(of episode: Playable) async {
        guard let place = try? await catalogue.place(of: episode.id, in: mode) else { return }
        open(place.series)
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
    /// item's page when there is nothing to play (FR-HOME-04, FR-HOME-07).
    func select(_ tile: HomeTile) {
        if let request = tile.request {
            play(request)
        } else if let page = tile.page {
            show(page)
        }
    }

    func openSearch() {
        path.append(.search)
    }

    /// Settings are a normal-mode screen: kids mode has no way in
    /// (FR-MODE-06).
    func openSettings() {
        guard mode == .normal else { return }
        path.append(.settings)
    }

    func open(_ series: SeriesSummary) {
        path.append(.series(series))
    }

    /// Opens an item's own page.
    func show(_ page: Destination) {
        path.append(page)
    }

    /// Something was chosen from search results.
    func open(_ pick: SearchPick) {
        switch pick {
        case .series(let series):
            open(series)
        case .single(let playable):
            // Its own page, as for a series (FR-CONTENT-03).
            show(.programme(playable))
        case .playable(let playable):
            // An episode plays; the way to its series is in its menu.
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
    /// rows are read again (FR-HOME-10). `unavailable` is what it was asked
    /// to play when NPO turned out not to have it any more: a tile that
    /// would play that says so from now on (FR-CONTENT-05, FR-LATER-11).
    func playbackEnded(unavailable: PlayRequest? = nil) async {
        playbacksEnded += 1
        if let unavailable {
            gone.insert(.playable(unavailable.playable.id))
        }
        await refresh()
    }
}
