//
//  ScriptedWatchHistory.swift
//  NPO light
//

#if DEBUG
import Foundation

/// A `WatchHistory` that is gone when the process is, for previews, for the
/// app when a test launches it, and for tests (ADR 0009). Debug builds only.
actor ScriptedWatchHistory: WatchHistory {
    private var lists: [Mode: WatchedList] = [:]

    init(_ entries: [WatchedEntry] = [], in mode: Mode = .normal) {
        var list = WatchedList()
        entries.reversed().forEach { list.record($0) }
        lists[mode] = list
    }

    func entries(in mode: Mode) -> [WatchedEntry] {
        lists[mode]?.entries ?? []
    }

    func entry(for id: ItemID, in mode: Mode) -> WatchedEntry? {
        lists[mode]?.entry(for: id)
    }

    func record(_ entry: WatchedEntry, in mode: Mode) {
        lists[mode, default: WatchedList()].record(entry)
    }

    func hide(_ id: ItemID, in mode: Mode) {
        lists[mode]?.hide(id)
    }
}

extension PlaybackCoordinator {
    /// A coordinator whose positions and entries go nowhere, for previews.
    static func scripted() -> PlaybackCoordinator {
        PlaybackCoordinator(watched: .scripted(),
                            order: EpisodeOrder(catalogue: ScriptedCatalogue()),
                            clock: SystemClock())
    }
}
#endif
