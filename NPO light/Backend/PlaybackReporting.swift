//
//  PlaybackReporting.swift
//  NPO light
//

import Foundation

/// One thing the player did, as NPO is told about it (FR-PLAY-12).
nonisolated struct PlaybackEvent: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        /// The stream was loaded, and is about to play.
        case loaded
        case started

        /// Nothing happened but playing: where it is by now.
        case waypoint
        case paused
        case resumed

        /// Somebody moved to another point, from this one.
        case sought(from: TimeInterval)

        /// It played to its end.
        case completed

        /// The player was left.
        case stopped
    }

    let kind: Kind
    let episode: EpisodeID

    /// Where playback is, in seconds.
    let position: TimeInterval

    /// How long the programme lasts, in seconds.
    let duration: TimeInterval
}

/// Telling NPO what plays, in the app's own terms (ADR 0008, ADR 0028).
///
/// It is how NPO comes to know a position at all: it keeps one for a profile
/// only when an app reports it (Q-12, Q-13).
nonisolated protocol PlaybackReporting: Sendable {
    /// Reports `event` as the NPO profile of `mode`. Throws when NPO did not
    /// take it; a caller has nothing to do about that but go on.
    func report(_ event: PlaybackEvent, in mode: Mode) async throws
}

/// Reports that go nowhere: for what is played instead of NPO's streams, and
/// for tests that are about something else (ADR 0019).
nonisolated struct NoReports: PlaybackReporting {
    func report(_ event: PlaybackEvent, in mode: Mode) async throws {}
}

/// A `PlaybackReporting` that logs every report NPO did not take
/// (ADR 0016).
nonisolated struct LoggedReports: PlaybackReporting {
    private let wrapped: any PlaybackReporting
    private let log: any Logging

    init(wrapping wrapped: any PlaybackReporting, log: any Logging) {
        self.wrapped = wrapped
        self.log = log
    }

    func report(_ event: PlaybackEvent, in mode: Mode) async throws {
        try await LoggedCall.run("report of \(event.episode.rawValue) in \(mode)", in: .playback, log: log) {
            try await wrapped.report(event, in: mode)
        }
    }
}
