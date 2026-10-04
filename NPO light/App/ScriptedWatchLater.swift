//
//  ScriptedWatchLater.swift
//  NPO light
//

#if DEBUG
import Foundation

/// A `WatchLater` that is gone when the process is, for previews, for the
/// app when a test launches it, and for tests (ADR 0009). Debug builds only.
actor ScriptedWatchLater: WatchLater {
    private var lists: [Mode: WatchLaterList] = [:]

    init(_ saved: [SavedItem] = [], in mode: Mode = .normal) {
        var list = WatchLaterList()
        saved.reversed().forEach { list.save($0) }
        lists[mode] = list
    }

    func saved(in mode: Mode) -> [SavedItem] {
        lists[mode]?.items ?? []
    }

    func save(_ item: SavedItem, in mode: Mode) {
        lists[mode, default: WatchLaterList()].save(item)
    }

    func remove(_ id: EpisodeID, in mode: Mode) {
        lists[mode]?.remove(id)
    }
}

extension WatchedState {
    /// Nothing watched and nothing saved, for previews.
    static func scripted() -> WatchedState {
        WatchedState(progress: ScriptedProgress(), history: ScriptedWatchHistory(), later: ScriptedWatchLater())
    }
}
#endif
