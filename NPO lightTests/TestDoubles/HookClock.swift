//
//  HookClock.swift
//  NPO lightTests
//

import Foundation
import Synchronization
@testable import NPO_light

/// A `Clocking` that never sleeps, and lets a test act at each wait: what
/// ``TestClock`` deliberately cannot express, for the few tests about
/// something happening while the code waits.
nonisolated final class HookClock: Clocking {
    private let hook = Mutex<(@MainActor @Sendable () -> Void)?>(nil)

    var now: Date { Date(timeIntervalSince1970: 0) }

    /// What to do each time something waits, on the main actor, before the
    /// wait returns.
    func onWait(_ action: @escaping @MainActor @Sendable () -> Void) {
        hook.withLock { $0 = action }
    }

    func wait(for duration: Duration) async throws {
        try Task.checkCancellation()
        let action = hook.withLock { $0 }
        await action?()
    }
}
