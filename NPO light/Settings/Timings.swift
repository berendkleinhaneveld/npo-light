//
//  Timings.swift
//  NPO light
//

import Foundation

/// The three durations the family can change (FR-SET-02), in seconds.
nonisolated struct Timings: Sendable, Equatable {
    enum Setting: String, Sendable, CaseIterable {
        /// The pause before the next episode in kids mode (FR-PLAY-06).
        case kidsPause
        /// How long kids mode plays before it asks whether anyone is still
        /// watching (FR-PLAY-08).
        case kidsStillWatching
        /// The same, in normal mode.
        case normalStillWatching

        /// What is offered: a few sensible values, not a number typed with a
        /// remote.
        var choices: [Int] {
            switch self {
            case .kidsPause: [0, 5, 10, 15, 30]
            case .kidsStillWatching: [1800, 3600, 5400, 7200]
            case .normalStillWatching: [3600, 7200, 10800, 14400]
            }
        }

        /// What a fresh install uses.
        var standard: Int {
            switch self {
            case .kidsPause: 5
            case .kidsStillWatching: 3600
            case .normalStillWatching: 10800
            }
        }
    }

    private var chosen: [Setting: Int] = [:]

    /// The value in use: what was chosen, or the default. Assigning something
    /// that is not one of the choices changes nothing.
    subscript(setting: Setting) -> Int {
        get { chosen[setting] ?? setting.standard }
        set {
            guard setting.choices.contains(newValue) else { return }
            chosen[setting] = newValue
        }
    }

    /// How long `mode` plays before it asks whether anyone is still watching.
    func stillWatching(in mode: Mode) -> Duration {
        .seconds(self[mode == .kids ? .kidsStillWatching : .normalStillWatching])
    }
}

/// The timings as they are kept: one value each in `UserDefaults`, read
/// through an accessor with a default (ADR 0012). A value that cannot be
/// read, or is none of the choices, is the default.
nonisolated struct StoredTimings: Sendable {
    /// Names the defaults to keep them in; `nil` is the app's own.
    let suite: String?

    init(suite: String? = nil) {
        self.suite = suite
    }

    var timings: Timings {
        var timings = Timings()
        for setting in Timings.Setting.allCases {
            if let stored = defaults.object(forKey: Self.key(setting)) as? Int {
                timings[setting] = stored
            }
        }
        return timings
    }

    func keep(_ value: Int, for setting: Timings.Setting) {
        defaults.set(value, forKey: Self.key(setting))
    }

    private var defaults: UserDefaults {
        suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    private static func key(_ setting: Timings.Setting) -> String {
        "settings.\(setting.rawValue)"
    }
}
