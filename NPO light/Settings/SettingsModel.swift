//
//  SettingsModel.swift
//  NPO light
//

import Foundation
import Observation

/// The settings screen's state: the timings, and the two things it can do
/// to this television (FR-SET-02, FR-SET-03, FR-SET-04).
///
/// It is also where playback reads the timings from, so that a changed value
/// is used at the next episode boundary without a relaunch.
@MainActor
@Observable
final class SettingsModel {
    private(set) var timings: Timings

    /// What was erased a moment ago, for the screen to say so.
    private(set) var erased: Set<Mode>?

    private let keep: (Int, Timings.Setting) -> Void
    private let eraser: any LocalDataErasing
    private let leave: () -> Void

    /// - Parameters:
    ///   - timings: the timings as they were kept.
    ///   - keep: writes a chosen value down for the next launch.
    ///   - signOut: forgets the session (FR-AUTH-04).
    init(timings: Timings,
         eraser: any LocalDataErasing,
         keep: @escaping (Int, Timings.Setting) -> Void,
         signOut: @escaping () -> Void) {
        self.timings = timings
        self.eraser = eraser
        self.keep = keep
        leave = signOut
    }

    /// One of a setting's choices was selected.
    func choose(_ value: Int, for setting: Timings.Setting) {
        timings[setting] = value
        guard timings[setting] == value else { return }
        keep(value, setting)
    }

    /// Erases what is kept for `modes`. The session is not touched
    /// (FR-SET-04).
    func erase(_ modes: Set<Mode>) async {
        await eraser.erase(modes)
        erased = modes
    }

    /// Forgets the session on this television, and nothing else: what is kept
    /// here stays (FR-SET-03, FR-AUTH-04).
    func signOut() {
        leave()
    }
}

#if DEBUG
extension SettingsModel {
    /// Settings that are gone with the process, for previews.
    static func scripted() -> SettingsModel {
        SettingsModel(timings: Timings(), eraser: ScriptedEraser(), keep: { _, _ in }, signOut: {})
    }
}
#endif
