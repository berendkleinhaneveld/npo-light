//
//  Flag.swift
//  NPO lightTests
//

import Synchronization

/// Something a test sets halfway, for a stand-in to answer differently from
/// then on: NPO's catalogue is not the same after a night.
nonisolated final class Flag: Sendable {
    private let value = Mutex(false)

    var isSet: Bool { value.withLock { $0 } }

    func set() {
        value.withLock { $0 = true }
    }
}
