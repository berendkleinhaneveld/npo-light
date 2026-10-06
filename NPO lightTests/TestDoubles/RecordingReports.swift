//
//  RecordingReports.swift
//  NPO lightTests
//

import Foundation
import Synchronization
@testable import NPO_light

/// A `PlaybackReporting` that remembers what it was told, and fails when a
/// test wants NPO not to take a report (ADR 0009).
nonisolated final class RecordingReports: PlaybackReporting {
    struct Report: Equatable {
        let event: PlaybackEvent
        let mode: Mode
    }

    private let received = Mutex<[Report]>([])
    private let failure: BackendError?

    init(failingWith failure: BackendError? = nil) {
        self.failure = failure
    }

    /// Every report, in the order it arrived.
    var reports: [Report] { received.withLock { $0 } }

    var kinds: [PlaybackEvent.Kind] { reports.map(\.event.kind) }

    func report(_ event: PlaybackEvent, in mode: Mode) async throws {
        received.withLock { $0.append(Report(event: event, mode: mode)) }
        if let failure { throw failure }
    }
}
