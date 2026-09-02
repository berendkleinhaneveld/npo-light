//
//  InMemoryTokenStore.swift
//  NPO lightTests
//

import Foundation
import Synchronization
@testable import NPO_light

/// A `TokenStore` that keeps the session in memory.
///
/// The real store is the Keychain, and it is not used here: the simulator's
/// keychain outlives a test run, which would make the suite order-dependent.
/// `KeychainTokenStore` gets its own integration tests instead, with a
/// per-run unique service name (ADR 0009).
nonisolated final class InMemoryTokenStore: TokenStore {
    private struct State {
        var session: Session?
        var saveCount = 0
    }

    private let state: Mutex<State>

    init(session: Session? = nil) {
        state = Mutex(State(session: session))
    }

    /// How many times a session was written. NPO's refresh tokens rotate, so a
    /// refresh that does not store its result leaves the session dead on the
    /// next attempt — the count is what a test asserts on.
    var saveCount: Int { state.withLock { $0.saveCount } }

    /// What is stored right now, read without going through `load()`.
    var storedSession: Session? { state.withLock { $0.session } }

    func load() throws -> Session? {
        state.withLock { $0.session }
    }

    func save(_ session: Session) throws {
        state.withLock { state in
            state.session = session
            state.saveCount += 1
        }
    }

    func clear() throws {
        state.withLock { $0.session = nil }
    }
}
