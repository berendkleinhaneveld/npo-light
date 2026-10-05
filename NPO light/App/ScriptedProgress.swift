//
//  ScriptedProgress.swift
//  NPO light
//

#if DEBUG
import Foundation

/// Positions that are gone when the process is, for previews, for the app
/// when a test launches it, and for tests that want to see what was written
/// where (ADR 0009). Debug builds only.
actor ScriptedProgress: ProgressKeeping {
    private var positions: [Mode: [EpisodeID: PlaybackProgress]] = [:]

    /// Every position given to ``note(_:in:)``, oldest first.
    private(set) var noted: [PlaybackProgress] = []

    /// Every position given to ``keep(_:in:)``, oldest first.
    private(set) var kept: [PlaybackProgress] = []

    init(_ known: [PlaybackProgress] = [], in mode: Mode = .normal) {
        positions[mode] = Dictionary(known.map { ($0.id, $0) }) { _, last in last }
    }

    func progress(of id: EpisodeID, in mode: Mode) -> PlaybackProgress? {
        positions[mode]?[id]
    }

    func progress(of ids: [EpisodeID], in mode: Mode) -> [EpisodeID: PlaybackProgress] {
        (positions[mode] ?? [:]).filter { ids.contains($0.key) }
    }

    func note(_ progress: PlaybackProgress, in mode: Mode) {
        noted.append(progress)
        positions[mode, default: [:]][progress.id] = progress
    }

    func keep(_ progress: PlaybackProgress, in mode: Mode) {
        kept.append(progress)
        positions[mode, default: [:]][progress.id] = progress
    }

    func erase(in mode: Mode) {
        positions[mode] = nil
    }
}

extension PlayerModel {
    /// A player with nothing to play, for previews.
    static func scripted(_ playable: Playable) -> PlayerModel {
        PlayerModel(playable: playable,
                    mode: .normal,
                    starter: ScriptedPlayback(),
                    positions: .scripted(),
                    clock: SystemClock())
    }
}
#endif
