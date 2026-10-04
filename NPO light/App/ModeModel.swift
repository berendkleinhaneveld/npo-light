//
//  ModeModel.swift
//  NPO light
//

import Foundation
import Observation

/// The mode the app was last in, kept where a relaunch finds it: one value in
/// `UserDefaults`, read through an accessor with a default (ADR 0012,
/// FR-MODE-01). Signing out does not touch it.
nonisolated struct StoredMode: Sendable {
    private static let key = "settings.mode"

    /// Names the defaults to keep it in; `nil` is the app's own. A test names
    /// a suite of its own.
    let suite: String?

    init(suite: String? = nil) {
        self.suite = suite
    }

    /// Normal mode on a fresh install, and for a value that cannot be read.
    var mode: Mode {
        get { defaults.string(forKey: Self.key).flatMap(Mode.init(rawValue:)) ?? .normal }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.key) }
    }

    private var defaults: UserDefaults {
        suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}

/// Which mode the app is in, and whether the other one can be switched to
/// (FR-MODE-01, FR-MODE-02).
@MainActor
@Observable
final class ModeModel {
    /// Whether the account has an NPO kids profile to browse as (ADR 0014).
    enum KidsProfile: Equatable {
        /// NPO has not answered yet, or could not be asked.
        case unknown
        case present
        case missing
    }

    private(set) var current: Mode
    private(set) var kidsProfile = KidsProfile.unknown

    private let catalogue: any Catalogue
    private let keep: (Mode) -> Void

    /// - Parameters:
    ///   - initial: the mode the app was last in.
    ///   - keep: writes the mode down for the next launch.
    init(initial: Mode, catalogue: any Catalogue, keep: @escaping (Mode) -> Void) {
        current = initial
        self.catalogue = catalogue
        self.keep = keep
    }

    /// The switch can be used: back to normal mode always, to kids mode only
    /// with a kids profile to browse as.
    var canSwitch: Bool {
        current == .kids || kidsProfile == .present
    }

    /// In place of the switch, the home page says why there is none
    /// (FR-MODE-02).
    var explainsMissingProfile: Bool {
        current == .normal && kidsProfile == .missing
    }

    /// Asks NPO which modes the account can use: when the home page appears,
    /// so that a kids profile made a minute ago is found without signing in
    /// again. A kids mode that was stored for an account without a kids
    /// profile falls back to normal mode (FR-MODE-04).
    func load() async {
        guard let modes = try? await catalogue.availableModes() else { return }
        kidsProfile = modes.contains(.kids) ? .present : .missing
        if current == .kids, kidsProfile == .missing {
            enter(.normal)
        }
    }

    /// The one action: to the other mode, with nothing asked (FR-MODE-02).
    func switchMode() {
        guard canSwitch else { return }
        enter(current == .normal ? .kids : .normal)
    }

    private func enter(_ mode: Mode) {
        current = mode
        keep(mode)
    }
}

#if DEBUG
extension ModeModel {
    /// A mode that is gone with the process, for previews and for the app
    /// when a test launches it.
    static func scripted(_ mode: Mode = .normal) -> ModeModel {
        ModeModel(initial: mode, catalogue: ScriptedCatalogue(), keep: { _ in })
    }
}
#endif
