//
//  HTTPLogArchive.swift
//  NPO light
//

import Foundation
import Synchronization

/// A directory of requests and responses, one file each, to be read after the
/// fact (NFR-DIAG-03).
///
/// It lives in `Caches`, which is the one place on an Apple TV an app may
/// fill and the system may empty (ADR 0015): nothing here is worth keeping
/// once it has been looked at.
nonisolated final class HTTPLogArchive: Sendable {
    /// How many files are left standing when a launch tidies up, so that a
    /// television nobody copies the files off does not fill with them.
    static let ceiling = 500

    let directory: URL

    private let written = Mutex(0)

    init(directory: URL) {
        self.directory = directory
    }

    /// The archive of this app, under `Caches`.
    convenience init?(fileManager: FileManager = .default) {
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        self.init(directory: caches.appending(path: "http-log", directoryHint: .isDirectory))
    }

    /// Writes `exchange` to a file of its own and answers with the file's name.
    func keep(_ exchange: HTTPExchange) throws -> String {
        let number = written.withLock { count in
            count += 1
            return count
        }
        let name = exchange.fileName(numbered: number)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try exchange.document().write(to: directory.appending(path: name), options: .atomic)
        return name
    }

    /// Removes the oldest files beyond `ceiling`. The names sort by time.
    func tidy(keeping ceiling: Int = HTTPLogArchive.ceiling) throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in files.dropLast(ceiling) {
            try FileManager.default.removeItem(at: file)
        }
    }
}
