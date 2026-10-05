//
//  PlayerModelDoubles.swift
//  NPO lightTests
//

import Foundation
@testable import NPO_light

extension PlayerModel {
    /// A player whose positions go nowhere, for the tests that are about
    /// something else.
    convenience init(playable: Playable, mode: Mode, starter: any PlaybackStarting) {
        self.init(playable: playable,
                  mode: mode,
                  starter: starter,
                  positions: .scripted(),
                  clock: TestClock())
    }
}

extension HomeModel {
    /// A home page where nothing was watched, for the tests that are about
    /// something else.
    convenience init(pins: any Pins, mode: Mode) {
        self.init(pins: pins,
                  watched: .scripted(),
                  catalogue: StubCatalogue(),
                  clock: TestClock(),
                  mode: mode)
    }
}
