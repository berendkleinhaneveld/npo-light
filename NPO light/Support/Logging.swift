//
//  Logging.swift
//  NPO light
//

import Foundation
import os

/// How much a line matters. The system decides what to keep from this: an
/// error is written to the device's log, the rest is only held in memory for
/// whoever is watching (ADR 0016).
nonisolated enum LogLevel: Sendable, Equatable {
    case info
    case error
}

/// The area a line is about, so that one of them can be watched on its own.
nonisolated enum LogCategory: String, Sendable, Equatable {
    case session
    case catalogue
    case playback
    case http
}

/// Somewhere to write a line, injected so that a test can read what was
/// written (ADR 0009, ADR 0016).
nonisolated protocol Logging: Sendable {
    func record(_ message: String, level: LogLevel, category: LogCategory)
}

/// The production log: the system's unified log, under the app's own
/// subsystem.
///
/// Everything is written as public. A line reaches here already fit to be
/// read — what may be in one is decided where it is composed (NFR-DIAG-01,
/// NFR-DIAG-03) — and the system's own redaction would turn every one of them
/// into `<private>` the moment no debugger is attached.
nonisolated struct SystemLog: Logging {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.bearduck.NPO-light"

    /// One line. The system cuts a message off at about a kilobyte, which is
    /// why whole responses go to files instead (ADR 0016).
    func record(_ message: String, level: LogLevel, category: LogCategory) {
        let logger = Logger(subsystem: Self.subsystem, category: category.rawValue)
        switch level {
        case .info:
            logger.info("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        }
    }
}

/// An error as a line in a log: which one, and what was underneath it.
nonisolated enum ErrorDescription {
    static func of(_ error: any Error) -> String {
        if let error = error as? BackendError {
            return String(describing: error)
        }
        return describe(error as NSError)
    }

    private static func describe(_ error: NSError) -> String {
        var line = "\(error.domain) \(error.code): \(error.localizedDescription)"
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            line += " (\(describe(underlying)))"
        }
        return line
    }
}
