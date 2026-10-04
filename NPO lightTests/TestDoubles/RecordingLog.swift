//
//  RecordingLog.swift
//  NPO lightTests
//

import Foundation
import Synchronization
@testable import NPO_light

/// A `Logging` that keeps what it was given, so that a test can read the log
/// (ADR 0009, ADR 0016).
nonisolated final class RecordingLog: Logging {
    struct Entry: Equatable, Sendable {
        let message: String
        let level: LogLevel
        let category: LogCategory
    }

    private let recorded = Mutex<[Entry]>([])

    /// Everything written so far, oldest first.
    var entries: [Entry] { recorded.withLock { $0 } }

    /// The messages alone, for a test that is about what was said.
    var messages: [String] { entries.map(\.message) }

    func record(_ message: String, level: LogLevel, category: LogCategory) {
        let entry = Entry(message: message, level: level, category: category)
        recorded.withLock { $0.append(entry) }
    }
}
