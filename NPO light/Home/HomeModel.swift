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
/// the home page comes back on screen, which is the price ADR 0011 names for
/// having no `@Query` (FR-HOME-10).
@MainActor
@Observable
final class HomeModel {
    var path: [Destination] = []

    /// What is playing. The player is presented over the stack rather than
    /// pushed onto it (ADR 0011).
    var playing: Playable?

    /// The pinned series, most recently pinned first (FR-HOME-02).
    private(set) var pinned: [SeriesSummary] = []

    let mode: Mode

    private let pins: any Pins

    init(pins: any Pins, mode: Mode) {
        self.pins = pins
        self.mode = mode
    }

    /// Reads the rows as they are kept now.
    func refresh() async {
        pinned = await pins.pinned(in: mode)
    }

    /// Takes a series off the pinned row, from the row itself (FR-HOME-05).
    func unpin(_ series: SeriesSummary) async {
        // A pin that could not be removed is still shown, as it is kept.
        try? await pins.unpin(series.id, in: mode)
        await refresh()
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
        case .playable(let playable):
            // Straight to playing: a single programme's own page has no
            // endpoint yet (Q-10).
            play(playable)
        }
    }

    func play(_ playable: Playable) {
        playing = playable
    }
}
