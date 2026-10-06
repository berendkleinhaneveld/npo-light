//
//  SharedPosition.swift
//  NPO light
//

import Foundation

/// How far NPO says something was watched, on whichever of the account's
/// devices that was (FR-PLAY-13).
nonisolated struct SharedPosition: Sendable, Hashable, Codable {
    /// NPO rounds a position on one page and not on another. Two that are
    /// this close are the same one.
    static let tolerance: TimeInterval = 1

    /// Where it was left, in seconds.
    let offset: TimeInterval

    /// The length NPO measured that against, when it can be told.
    let duration: TimeInterval?

    /// Whether this is the position NPO reported before, at `known`.
    func isSame(as known: TimeInterval?) -> Bool {
        guard let known else { return false }
        return abs(known - offset) < Self.tolerance
    }
}

/// Something NPO lists for a profile to go on with: its own *Kijk verder*
/// (FR-HOME-12).
nonisolated struct Continued: Sendable, Equatable {
    /// What to go on with, and how far in it is.
    let playable: Playable

    /// Whether NPO presents it as a programme with a page of its own. Anything
    /// else is an episode, of a series the list does not name (Q-10).
    let isSingle: Bool
}
