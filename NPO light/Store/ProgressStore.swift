//
//  ProgressStore.swift
//  NPO light
//

import Foundation
import SwiftData

/// The playback positions of each mode (ADR 0011, ADR 0012).
nonisolated protocol ProgressKeeping: Sendable {
    func progress(of id: EpisodeID, in mode: Mode) async -> PlaybackProgress?

    /// Writes a position while something plays: to the store, and no further
    /// (ADR 0018).
    func note(_ progress: PlaybackProgress, in mode: Mode) async throws

    /// Writes a position at a point where playback rests — a pause, a stop,
    /// the finish: to the store, and to the copy tvOS cannot take
    /// (NFR-REL-04).
    func keep(_ progress: PlaybackProgress, in mode: Mode) async throws
}

/// The positions the copy in `UserDefaults` holds for one mode, newest first.
nonisolated struct PositionCopy: Sendable, Equatable, Codable {
    var positions: [PlaybackProgress] = []
}

/// Every position, in a SwiftData store in `Caches`, with the most recent
/// ones copied to `UserDefaults` (ADR 0015).
///
/// tvOS may empty `Caches` while the app is not running. A store that is not
/// there when the app starts is filled again from the copy, and that is not a
/// reset: nothing the family chose was lost.
actor ProgressStore: ProgressKeeping, ModelActor {
    /// The most one mode's copy may take. The lists the family made come
    /// first: with both modes' copies full they still have a third of the
    /// ceiling to themselves (ADR 0018).
    static let copyBudget = 128 * 1024

    nonisolated let modelExecutor: any ModelExecutor
    nonisolated let modelContainer: ModelContainer

    /// Whether a store that was there could not be read and was started over
    /// (NFR-REL-05).
    nonisolated let wasReset: Bool

    private let defaults: LocalDefaults
    private let copyBudget: Int
    private var isFilled: Bool

    /// - Parameter isNew: the store held nothing when it was opened, and is
    ///   to be filled from the copy before it is first used.
    init(container: ModelContainer,
         isNew: Bool,
         wasReset: Bool = false,
         suite: String? = nil,
         ceiling: Int = LocalDefaults.ceiling,
         copyBudget: Int = ProgressStore.copyBudget) {
        modelContainer = container
        modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(container))
        defaults = LocalDefaults(suite: suite, ceiling: ceiling)
        self.copyBudget = copyBudget
        self.wasReset = wasReset
        isFilled = !isNew
    }

    // MARK: ProgressKeeping

    func progress(of id: EpisodeID, in mode: Mode) -> PlaybackProgress? {
        fillIfNew()
        return stored(id, in: mode)?.progress
    }

    func note(_ progress: PlaybackProgress, in mode: Mode) throws {
        fillIfNew()
        try write(progress, in: mode)
    }

    func keep(_ progress: PlaybackProgress, in mode: Mode) throws {
        fillIfNew()
        try write(progress, in: mode)
        copy(progress, in: mode)
    }

    // MARK: The store

    private func stored(_ id: EpisodeID, in mode: Mode) -> StoredProgress? {
        let episode = id.rawValue
        let modeName = mode.rawValue
        var request = FetchDescriptor<StoredProgress>(
            predicate: #Predicate { $0.mode == modeName && $0.episode == episode }
        )
        request.fetchLimit = 1
        return try? modelContext.fetch(request).first
    }

    private func write(_ progress: PlaybackProgress, in mode: Mode) throws {
        if let existing = stored(progress.id, in: mode) {
            existing.take(progress)
        } else {
            modelContext.insert(StoredProgress(progress, mode: mode))
        }
        try modelContext.save()
    }

    // MARK: The copy

    /// Puts `progress` at the front of the mode's copy and drops the oldest
    /// until it fits: under its own budget, and under the ceiling everything
    /// in `UserDefaults` shares. A copy that cannot be written is not an
    /// error: the store has the position.
    private func copy(_ progress: PlaybackProgress, in mode: Mode) {
        var copy = defaults.value(PositionCopy.self, for: .positions, in: mode) ?? PositionCopy()
        copy.positions.removeAll { $0.id == progress.id }
        copy.positions.insert(progress, at: 0)
        let room = min(copyBudget, defaults.room(for: .positions, in: mode))
        let encoder = JSONEncoder()
        while !copy.positions.isEmpty {
            if let data = try? encoder.encode(copy), data.count <= room {
                try? defaults.write(data, for: .positions, in: mode)
                return
            }
            // A tenth at a time, and at least one: this runs once in a
            // thousand positions, not at every write.
            copy.positions.removeLast(max(1, copy.positions.count / 10))
        }
        defaults.remove(.positions, in: mode)
    }

    /// Fills a store that held nothing from the copy, once.
    private func fillIfNew() {
        guard !isFilled else { return }
        isFilled = true
        for mode in Mode.allCases {
            let copy = defaults.value(PositionCopy.self, for: .positions, in: mode) ?? PositionCopy()
            for progress in copy.positions where stored(progress.id, in: mode) == nil {
                modelContext.insert(StoredProgress(progress, mode: mode))
            }
        }
        // A store that cannot be saved is found out at the next write.
        try? modelContext.save()
    }
}

extension ProgressStore {
    private static let fileName = "positions.store"

    /// Opens the store in `directory`, which is the app's `Caches` — never a
    /// default configuration, which resolves somewhere a television refuses
    /// (ADR 0015).
    ///
    /// A store that cannot be opened is removed and started over rather than
    /// taking the app down with it at every launch (NFR-REL-05), and if even
    /// that fails the positions are kept in memory for this run.
    static func open(in directory: URL, suite: String? = nil) -> ProgressStore {
        let url = directory.appending(path: fileName)
        let existed = FileManager.default.fileExists(atPath: url.path())
        if let container = try? container(ModelConfiguration(url: url)) {
            return ProgressStore(container: container, isNew: !existed, suite: suite)
        }
        remove(url)
        if let container = try? container(ModelConfiguration(url: url)) {
            return ProgressStore(container: container, isNew: true, wasReset: existed, suite: suite)
        }
        return inMemory(isNew: true, wasReset: existed, suite: suite)
    }

    /// A store that is gone with the process: the last resort of ``open(in:suite:)``,
    /// and what a test uses.
    static func inMemory(isNew: Bool = false, wasReset: Bool = false, suite: String? = nil) -> ProgressStore {
        do {
            let container = try container(ModelConfiguration(isStoredInMemoryOnly: true))
            return ProgressStore(container: container, isNew: isNew, wasReset: wasReset, suite: suite)
        } catch {
            fatalError("A SwiftData store in memory could not be created: \(error)")
        }
    }

    private static func container(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: StoredProgress.self, configurations: configuration)
    }

    /// The store and the two files SQLite keeps beside it.
    private static func remove(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(filePath: url.path() + suffix))
        }
    }
}
