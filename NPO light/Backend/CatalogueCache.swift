//
//  CatalogueCache.swift
//  NPO light
//

import Foundation

/// What NPO answered about a series, a season or a programme, kept on the
/// television so that a page seen before can be drawn without the network
/// (FR-CONTENT-04, ADR 0024).
///
/// One file an answer, in `Caches`, under two ceilings: a number of answers
/// and a number of bytes. The oldest go first (NFR-PERF-04). tvOS may empty
/// the directory at any time, and nothing is lost by that but a round trip.
actor CatalogueCache {
    nonisolated enum Kind: String, Sendable {
        case series
        case episodes
        case programme
    }

    /// What an answer is about. The mode is part of it: the two modes browse
    /// different catalogues (FR-MODE-04).
    nonisolated struct Key: Sendable, Hashable {
        let kind: Kind
        let identifier: String
        let mode: Mode

        /// A file name: the identifiers are NPO's, so only what is safe in
        /// one is kept.
        var fileName: String {
            let safe = identifier.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            return "\(mode.rawValue)-\(kind.rawValue)-\(safe).json"
        }
    }

    /// How soon an answer is asked for again: how fast what it is about
    /// changes (ADR 0024).
    nonisolated enum Pace: String, Sendable, Codable {
        /// A programme followed as it is broadcast — the news, a daily
        /// programme: a new episode is wanted the evening it is there.
        case current

        /// The latest season of any other series, and the series itself:
        /// when it is still running, an episode or a season is added now
        /// and then.
        case running

        /// What does not change any more: an earlier season, a film.
        case settled

        /// How long an answer of this pace is given without asking again.
        var age: TimeInterval {
            switch self {
            case .current: 30 * 60
            case .running: 24 * 60 * 60
            case .settled: 7 * 24 * 60 * 60
            }
        }
    }

    /// An answer, when NPO gave it, and how soon it is to be asked for again.
    /// An answer kept before the pace was is asked for soonest.
    nonisolated struct Entry<Value: Codable & Sendable>: Codable, Sendable {
        let value: Value
        let fetchedAt: Date
        var pace: Pace?
    }

    /// The most answers kept. A family's series, seasons and films of a year
    /// fit several times over.
    static let entryCeiling = 400

    /// The most bytes kept. A long season is about a hundred kilobytes.
    static let byteCeiling = 16 * 1024 * 1024

    private let directory: URL
    private let entryCeiling: Int
    private let byteCeiling: Int

    /// What is on disk, by file name: its size and when it was fetched. Read
    /// from the directory once, on first use.
    private var index: [String: (size: Int, fetchedAt: Date)]?

    init(directory: URL,
         entryCeiling: Int = CatalogueCache.entryCeiling,
         byteCeiling: Int = CatalogueCache.byteCeiling) {
        self.directory = directory
        self.entryCeiling = entryCeiling
        self.byteCeiling = byteCeiling
    }

    /// The cache of this app, under `Caches`.
    init?(named name: String = "catalogue") {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        self.init(directory: caches.appending(path: name, directoryHint: .isDirectory))
    }

    /// What is kept for `key`. Nothing kept, or something that cannot be
    /// read — written by another version of the app, say — is `nil`.
    func entry<Value: Codable & Sendable>(_ type: Value.Type, for key: Key) -> Entry<Value>? {
        guard let data = try? Data(contentsOf: file(key)) else { return nil }
        return try? JSONDecoder().decode(Entry<Value>.self, from: data)
    }

    /// Keeps `value` as NPO's answer at `date`, and makes room for it.
    func store(_ value: some Codable & Sendable, for key: Key, at date: Date, pace: Pace = .current) {
        guard let data = try? JSONEncoder().encode(Entry(value: value, fetchedAt: date, pace: pace)) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A cache that cannot be written is a cache that is empty.
        guard (try? data.write(to: file(key), options: .atomic)) != nil else { return }
        // The file's own date is when NPO answered: it is what a later
        // launch orders the answers by, without opening them.
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file(key).path())
        var known = loadedIndex()
        known[key.fileName] = (data.count, date)
        index = known
        evict()
    }

    func remove(_ key: Key) {
        try? FileManager.default.removeItem(at: file(key))
        index?[key.fileName] = nil
    }

    /// Forgets everything kept for `mode`: what was browsed says something
    /// about who browsed (FR-SET-04, NFR-PRIV-04).
    func erase(_ mode: Mode) {
        for name in loadedIndex().keys where name.hasPrefix("\(mode.rawValue)-") {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
            index?[name] = nil
        }
    }

    /// How many answers are kept, and in how many bytes.
    var footprint: (entries: Int, bytes: Int) {
        let known = loadedIndex()
        return (known.count, known.values.reduce(0) { $0 + $1.size })
    }

    private func file(_ key: Key) -> URL {
        directory.appending(path: key.fileName)
    }

    /// Removes the oldest answers until both ceilings hold.
    private func evict() {
        var known = loadedIndex()
        var bytes = known.values.reduce(0) { $0 + $1.size }
        let oldestFirst = known.sorted { $0.value.fetchedAt < $1.value.fetchedAt }.map(\.key)
        for name in oldestFirst where known.count > entryCeiling || bytes > byteCeiling {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
            bytes -= known[name]?.size ?? 0
            known[name] = nil
        }
        index = known
    }

    /// The files as they are, on first use. A file's modification date
    /// stands in for when it was fetched: it was written then.
    private func loadedIndex() -> [String: (size: Int, fetchedAt: Date)] {
        if let index { return index }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: Array(keys))) ?? []
        var found: [String: (size: Int, fetchedAt: Date)] = [:]
        for file in files {
            let values = try? file.resourceValues(forKeys: keys)
            found[file.lastPathComponent] = (values?.fileSize ?? 0, values?.contentModificationDate ?? .distantPast)
        }
        index = found
        return found
    }
}
