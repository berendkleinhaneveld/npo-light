//
//  LaunchNotice.swift
//  NPO light
//

import Foundation
import Observation

/// What this launch has to tell the user once: that the store of positions
/// could not be read and was started over (NFR-REL-05).
///
/// A store that tvOS emptied is not that: it is filled again from its copy,
/// and nobody is told (ADR 0015).
@MainActor
@Observable
final class LaunchNotice {
    private(set) var positionsWereReset: Bool

    init(positionsWereReset: Bool) {
        self.positionsWereReset = positionsWereReset
    }

    /// The user has read it. It is not said again, in either mode.
    func acknowledge() {
        positionsWereReset = false
    }
}
