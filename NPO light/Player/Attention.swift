//
//  Attention.swift
//  NPO light
//

import Foundation

/// How long something has played without anybody touching the remote: what
/// the still-watching prompt turns on (FR-PLAY-08).
///
/// It counts across episodes: the next one starting by itself is nobody
/// touching anything.
nonisolated struct Attention: Sendable, Equatable {
    /// How long the prompt waits for an answer before playback stops.
    static let grace = 30

    /// How long after the app itself started, paused or moved the player a
    /// change in the player is taken to be the app's own, and nobody's
    /// interaction.
    static let settling: TimeInterval = 2

    /// When somebody last did something.
    private(set) var since: Date

    private var quietUntil: Date

    init(at now: Date) {
        since = now
        quietUntil = now
    }

    /// The app is about to start, pause or move the player itself.
    mutating func expectOwnChange(at now: Date) {
        quietUntil = now.addingTimeInterval(Self.settling)
    }

    /// The player was paused, resumed or scrubbed. Unless the app just did
    /// that itself, somebody is there.
    mutating func noticed(at now: Date) {
        guard now >= quietUntil else { return }
        since = now
    }

    /// Somebody answered the prompt.
    mutating func confirmed(at now: Date) {
        since = now
    }

    /// Whether it has played for `limit` with nobody there.
    func isDue(at now: Date, after limit: Duration) -> Bool {
        let (seconds, attoseconds) = limit.components
        return now.timeIntervalSince(since) >= TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
