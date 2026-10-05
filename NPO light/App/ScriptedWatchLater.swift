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

    func erase(in mode: Mode) {
        lists[mode] = nil
    }
}

/// Erases the scripted stores, which keep nothing in `UserDefaults`.
nonisolated struct ScriptedEraser: LocalDataErasing {
    let pins: ScriptedPins
    let history: ScriptedWatchHistory
    let later: ScriptedWatchLater
    let progress: ScriptedProgress
    let searches: ScriptedSearchHistory

    init(pins: ScriptedPins = ScriptedPins(),
         history: ScriptedWatchHistory = ScriptedWatchHistory(),
         later: ScriptedWatchLater = ScriptedWatchLater(),
         progress: ScriptedProgress = ScriptedProgress(),
         searches: ScriptedSearchHistory = ScriptedSearchHistory()) {
        self.pins = pins
        self.history = history
        self.later = later
        self.progress = progress
        self.searches = searches
    }

    func erase(_ modes: Set<Mode>) async {
        for mode in modes {
            await pins.erase(in: mode)
            await history.erase(in: mode)
            await later.erase(in: mode)
            await progress.erase(in: mode)
            await searches.clear(in: mode)
        }
    }
}

extension ScriptedEraser {
    /// The environment variable a UI test sets to start on a home page with
    /// something on every row.
    static let filledKey = "NPO_LIGHT_HOME"

    /// Three things on *Kijk verder* and one saved for later, for a test of
    /// what the home page does when one of them goes.
    static func filled() -> ScriptedEraser {
        let results = ScriptedCatalogue.results
        let film = results.singleProgrammes[0]
        let played = Date(timeIntervalSinceNow: -3600)
        let entries = results.series.enumerated().map { index, series in
            WatchedEntry(series: series,
                         next: Upcoming(results.episodes[0], in: ScriptedCatalogue.seasons[0].id),
                         playedAt: played.addingTimeInterval(TimeInterval(-index)))
        } + [WatchedEntry(single: film, playedAt: played.addingTimeInterval(-60))]
        return ScriptedEraser(history: ScriptedWatchHistory(entries),
                              later: ScriptedWatchLater([SavedItem(film, origin: .single)]))
    }
}

extension WatchedState {
    /// Nothing watched and nothing saved, for previews.
    static func scripted() -> WatchedState {
        WatchedState(progress: ScriptedProgress(), history: ScriptedWatchHistory(), later: ScriptedWatchLater())
    }
}
#endif
