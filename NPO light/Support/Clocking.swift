//
//  Clocking.swift
//  NPO light
//

import Foundation

/// The passage of time, injected so that tests never sleep (NFR-MAINT-04).
///
/// Deliberately narrower than the standard library's `Clock`: this app asks
/// what time it is, and waits a while. A fake for two operations is a handful
/// of lines, where a correct `Clock` conformance — instant advancement,
/// cancellation, waker ordering — is not (ADR 0009).
nonisolated protocol Clocking: Sendable {
    /// Wall time, for token expiry and the sign-in window.
    var now: Date { get }

    /// Suspends for `duration`, throwing `CancellationError` if the task is
    /// cancelled while it waits.
    func wait(for duration: Duration) async throws
}

/// The production clock.
nonisolated struct SystemClock: Clocking {
    var now: Date { Date() }

    func wait(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
