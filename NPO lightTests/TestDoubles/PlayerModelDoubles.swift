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
                  positions: .scripted())
    }
}
