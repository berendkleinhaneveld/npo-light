//
//  ScriptedPins.swift
//  NPO light
//

#if DEBUG
import Foundation

/// `Pins` that are gone when the process is, for previews and for the app
/// when a test launches it (ADR 0009). Debug builds only.
actor ScriptedPins: Pins {
    private var lists: [Mode: PinList] = [:]

    init(_ pinned: [SeriesSummary] = [], in mode: Mode = .normal) {
        var list = PinList()
        pinned.reversed().forEach { list.pin($0) }
        lists[mode] = list
    }

    func pinned(in mode: Mode) -> [SeriesSummary] {
        lists[mode]?.series ?? []
    }

    func isPinned(_ id: ItemID, in mode: Mode) -> Bool {
        lists[mode]?.contains(id) ?? false
    }

    func pin(_ series: SeriesSummary, in mode: Mode) {
        lists[mode, default: PinList()].pin(series)
    }

    func unpin(_ id: ItemID, in mode: Mode) {
        lists[mode]?.unpin(id)
    }
}

extension HomeModel {
    /// A home page with these series pinned, for previews.
    static func scripted(pinned: [SeriesSummary] = [], mode: Mode = .normal) -> HomeModel {
        HomeModel(pins: ScriptedPins(pinned, in: mode),
                  watched: .scripted(),
                  catalogue: ScriptedCatalogue(),
                  clock: SystemClock(),
                  mode: mode)
    }
}

extension SeriesDetailModel {
    /// A series page over the scripted catalogue, for previews.
    static func scripted(_ summary: SeriesSummary) -> SeriesDetailModel {
        SeriesDetailModel(summary: summary,
                          catalogue: ScriptedCatalogue(),
                          pins: ScriptedPins(),
                          watched: .scripted(),
                          mode: .normal)
    }
}
#endif
