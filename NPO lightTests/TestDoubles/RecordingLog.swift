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
    private let stream: AsyncStream<Entry>
    private let continuation: AsyncStream<Entry>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: Entry.self)
    }

    /// Everything written so far, oldest first.
    var entries: [Entry] { recorded.withLock { $0 } }

    /// The messages alone, for a test that is about what was said.
    var messages: [String] { entries.map(\.message) }

    func record(_ message: String, level: LogLevel, category: LogCategory) {
        let entry = Entry(message: message, level: level, category: category)
        recorded.withLock { $0.append(entry) }
        continuation.yield(entry)
    }

    /// The next line written, for what is logged from somewhere a test cannot
    /// await — the system player reports on a queue of its own.
    func next() async -> Entry? {
        for await entry in stream { return entry }
        return nil
    }
}
