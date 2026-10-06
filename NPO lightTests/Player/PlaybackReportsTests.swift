//
//  PlaybackReportsTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// What a sitting tells NPO and when, worked out from positions alone.
@MainActor
struct PlaybackReportsTests {
    private static let episode = EpisodeID(rawValue: "episode-1")

    private let reporter = RecordingReports()

    private static func moment(_ position: TimeInterval,
                               of duration: TimeInterval? = 600,
                               in mode: Mode = .normal) -> PlaybackReports.Moment {
        PlaybackReports.Moment(episode: episode, position: position, duration: duration, mode: mode)
    }

    @Test("FR-PLAY-12: starting is reported with the position playback starts from")
    func startIsReported() async {
        let reports = PlaybackReports(reporter: reporter)

        reports.began(Self.moment(120))
        await reports.sending?.value

        #expect(reporter.kinds == [.loaded, .started])
        #expect(reporter.reports.map(\.event.position) == [120, 120])
        #expect(reporter.reports.first?.event.duration == 600)
        #expect(reporter.reports.first?.event.episode == Self.episode)
    }

    @Test("FR-PLAY-12: while something plays, a position is reported for every thirty seconds of it")
    func waypointEveryThirtySeconds() async {
        let reports = PlaybackReports(reporter: reporter)
        reports.began(Self.moment(0))

        for position in stride(from: 10, through: 70, by: 10) {
            reports.ticked(Self.moment(TimeInterval(position)))
        }
        await reports.sending?.value

        let waypoints = reporter.reports.filter { $0.event.kind == .waypoint }
        #expect(waypoints.map(\.event.position) == [30, 60])
        #expect(PlaybackReports.waypointInterval == 30)
    }

    @Test("FR-PLAY-12: pausing and playing again are each reported once, where they happened")
    func pauseAndResumeAreReported() async {
        let reports = PlaybackReports(reporter: reporter)
        reports.began(Self.moment(0))

        // The player says that it plays when it starts, too: that is not
        // playing again.
        reports.resumed(Self.moment(1))
        reports.paused(Self.moment(42))
        reports.paused(Self.moment(42))
        reports.ticked(Self.moment(42))
        reports.resumed(Self.moment(42))
        await reports.sending?.value

        #expect(reporter.kinds == [.loaded, .started, .paused, .resumed])
        #expect(reporter.reports.last?.event.position == 42)
    }

    @Test("FR-PLAY-12: moving to another point is reported with where from and where to")
    func seekIsReported() async {
        let reports = PlaybackReports(reporter: reporter)
        reports.began(Self.moment(10))

        reports.sought(from: 15, to: Self.moment(400))
        // From there the thirty seconds start again.
        reports.ticked(Self.moment(410))
        reports.ticked(Self.moment(430))
        await reports.sending?.value

        #expect(reporter.kinds == [.loaded, .started, .sought(from: 15), .waypoint])
        #expect(reporter.reports.map(\.event.position) == [10, 10, 400, 430])
    }

    @Test("FR-PLAY-12: a jump nobody reported as one is still told at the next look")
    func unannouncedJumpIsCaughtUpWith() async {
        let reports = PlaybackReports(reporter: reporter)
        reports.began(Self.moment(500))

        reports.ticked(Self.moment(100))
        await reports.sending?.value

        #expect(reporter.kinds.last == .waypoint)
        #expect(reporter.reports.last?.event.position == 100)
    }

    @Test("FR-PLAY-12: reaching the end and leaving the player are reported")
    func endAndLeavingAreReported() async {
        let reports = PlaybackReports(reporter: reporter)
        reports.began(Self.moment(580))

        reports.completed(Self.moment(600))
        reports.stopped(Self.moment(600))
        // Closed twice, as a player that is dismissed and then disappears is.
        reports.stopped(Self.moment(600))
        await reports.sending?.value

        #expect(reporter.kinds == [.loaded, .started, .completed, .stopped])
    }

    @Test("FR-PLAY-12: leaving a player in which nothing began tells NPO nothing")
    func leavingBeforeAnythingBeganIsQuiet() async {
        let reports = PlaybackReports(reporter: reporter)

        reports.stopped(Self.moment(0))
        await reports.sending?.value

        #expect(reporter.reports.isEmpty)
    }

    @Test("FR-PLAY-12, FR-MODE-05: a report is made in the mode it was played in")
    func reportIsMadeInItsMode() async {
        let reports = PlaybackReports(reporter: reporter)

        reports.began(Self.moment(0, in: .kids))
        await reports.sending?.value

        #expect(reporter.reports.map(\.mode) == [.kids, .kids])
    }

    @Test("FR-PLAY-12: nothing is reported about something whose length is not known", arguments: [
        nil, TimeInterval.nan, 0
    ])
    func unknownLengthIsNotReported(duration: TimeInterval?) async {
        let reports = PlaybackReports(reporter: reporter)

        reports.began(Self.moment(10, of: duration))
        reports.paused(Self.moment(20, of: duration))
        await reports.sending?.value

        #expect(reporter.reports.isEmpty)
    }

    @Test("FR-PLAY-12: a report NPO does not take is dropped, and the ones after it still go")
    func failedReportIsDropped() async {
        let failing = RecordingReports(failingWith: .unreachable)
        let reports = PlaybackReports(reporter: failing)

        reports.began(Self.moment(0))
        reports.stopped(Self.moment(50))
        await reports.sending?.value

        #expect(failing.kinds == [.loaded, .started, .stopped])
    }
}
