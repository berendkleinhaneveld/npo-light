//
//  TestClock.swift
//  NPO lightTests
//

import Foundation
import Synchronization
@testable import NPO_light

/// A `Clocking` that never sleeps.
///
/// `wait(for:)` returns at once, moves ``now`` forward by what it was asked
/// for, and records it. A five-second poll interval is then assertable without
/// a five-second test, which is the point of injecting a clock at all.
///
/// It deliberately cannot express "the code is still waiting". No test needs
/// that yet, and buying it means suspending on continuations and the deadlocks
/// that come with them — add it when something needs it, not before (ADR 0009).
nonisolated final class TestClock: Clocking {
    private struct State {
        var now: Date
        var waits: [Duration] = []
    }

    private let state: Mutex<State>

    init(now: Date = Date(timeIntervalSince1970: 0)) {
        state = Mutex(State(now: now))
    }

    var now: Date { state.withLock { $0.now } }

    /// Every wait asked for, in order. This is how a test checks that a poll
    /// used the interval NPO advertised rather than one of its own choosing.
    var waits: [Duration] { state.withLock { $0.waits } }

    func wait(for duration: Duration) async throws {
        try Task.checkCancellation()
        state.withLock { state in
            state.waits.append(duration)
            state.now += duration.timeInterval
        }
    }

    /// Moves time on without a wait, for the expiry that happens while nothing
    /// is waiting — a session that lapses between launches, say.
    func advance(by duration: Duration) {
        state.withLock { $0.now += duration.timeInterval }
    }
}

extension Duration {
    /// Seconds, for the arithmetic `Date` wants.
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
