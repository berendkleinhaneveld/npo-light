//
//  PlaybackReports.swift
//  NPO light
//

import Foundation

/// What one sitting at the player tells NPO, and when (FR-PLAY-12).
///
/// It knows positions as numbers and nothing about a player, like the
/// coordinator beside it, and it sends one report after another: NPO keeps
/// the position of the last one it hears.
@MainActor
final class PlaybackReports {
    /// The most that plays between two reports: how far behind NPO can be.
    static let waypointInterval: TimeInterval = 30

    /// Where playback of something is.
    struct Moment: Equatable {
        let episode: EpisodeID
        let position: TimeInterval

        /// `nil`, or not a number, while nobody knows.
        let duration: TimeInterval?
        let mode: Mode
    }

    private let reporter: any PlaybackReporting

    /// The position NPO was last told.
    private var told: TimeInterval?
    private var isPaused = false

    /// Something began and the player was not left since.
    private var isOpen = false

    /// The latest report, while it is on its way.
    private(set) var sending: Task<Void, Never>?

    init(reporter: any PlaybackReporting) {
        self.reporter = reporter
    }

    /// Something was loaded and plays from here.
    func began(_ moment: Moment) {
        isOpen = true
        isPaused = false
        send(.loaded, at: moment)
        send(.started, at: moment)
    }

    /// The interval at which the player looks came round. A report goes out
    /// when playback is ``waypointInterval`` from the last one — or further,
    /// either way, which is somebody having moved it.
    func ticked(_ moment: Moment) {
        guard !isPaused, let told, abs(moment.position - told) >= Self.waypointInterval else { return }
        send(.waypoint, at: moment)
    }

    func paused(_ moment: Moment) {
        guard !isPaused else { return }
        isPaused = true
        send(.paused, at: moment)
    }

    /// It plays again. Playing for the first time is not this.
    func resumed(_ moment: Moment) {
        guard isPaused else { return }
        isPaused = false
        send(.resumed, at: moment)
    }

    /// Somebody moved from `origin` to where `moment` is.
    func sought(from origin: TimeInterval, to moment: Moment) {
        guard origin.isFinite else { return }
        send(.sought(from: origin), at: moment)
    }

    func completed(_ moment: Moment) {
        send(.completed, at: moment)
    }

    /// The player was left. Said once, however often it is closed.
    func stopped(_ moment: Moment) {
        guard isOpen else { return }
        isOpen = false
        send(.stopped, at: moment)
    }

    /// Nothing is said about something whose length is not known: NPO would
    /// make a share of nothing out of it.
    private func send(_ kind: PlaybackEvent.Kind, at moment: Moment) {
        guard let duration = moment.duration, duration.isFinite, duration > 0,
              moment.position.isFinite, moment.position >= 0 else { return }
        told = moment.position
        let event = PlaybackEvent(kind: kind, episode: moment.episode, position: moment.position, duration: duration)
        sending = Task { [reporter, previous = sending, mode = moment.mode] in
            await previous?.value
            // A report NPO did not take is dropped: the next one carries a
            // later position anyway, and what plays must not wait for it.
            try? await reporter.report(event, in: mode)
        }
    }
}
