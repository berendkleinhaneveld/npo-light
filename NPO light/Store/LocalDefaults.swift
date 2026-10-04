//
//  LocalDefaults.swift
//  NPO light
//

import Foundation

/// What can go wrong keeping something on this television.
nonisolated enum LocalDataError: Error, Equatable {
    /// The write would take the app's `UserDefaults` past its ceiling. It is
    /// refused: past a megabyte tvOS ends the process (ADR 0015).
    case full
}

/// The part of `UserDefaults` that holds what the family chose, under one
/// fixed ceiling (ADR 0015, NFR-REL-04).
///
/// One value per kind of record and per mode: the mode is in the key, so that
/// nothing kept for one mode can be read as the other's (FR-MODE-05).
///
/// Not `Sendable`, because `UserDefaults` is not: each store makes its own
/// from the name of the suite and keeps it inside its actor. Two of them over
/// one suite see the same values.
nonisolated struct LocalDefaults {
    /// What is kept here. Every kind counts towards the ceiling.
    enum Record: String, CaseIterable, Sendable {
        case searchHistory = "search-history"
    }

    /// Comfortably below the 512 KB at which tvOS starts to warn.
    static let ceiling = 384 * 1024

    let ceiling: Int

    private let defaults: UserDefaults

    /// `suite` names the defaults to keep things in; `nil` is the app's own.
    /// A test names a suite of its own and never touches those.
    init(suite: String? = nil, ceiling: Int = LocalDefaults.ceiling) {
        defaults = suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.ceiling = ceiling
    }

    /// Everything kept here, in bytes, for both modes.
    var size: Int {
        Record.allCases.reduce(0) { total, record in
            total + Mode.allCases.reduce(0) { $0 + (data(for: record, in: $1)?.count ?? 0) }
        }
    }

    func data(for record: Record, in mode: Mode) -> Data? {
        defaults.data(forKey: Self.key(record, mode))
    }

    /// Replaces what is kept for `record` in `mode`, unless that would cross
    /// the ceiling.
    func write(_ data: Data, for record: Record, in mode: Mode) throws {
        let replaced = self.data(for: record, in: mode)?.count ?? 0
        guard size - replaced + data.count <= ceiling else {
            throw LocalDataError.full
        }
        defaults.set(data, forKey: Self.key(record, mode))
    }

    func remove(_ record: Record, in mode: Mode) {
        defaults.removeObject(forKey: Self.key(record, mode))
    }

    private static func key(_ record: Record, _ mode: Mode) -> String {
        "local.\(record.rawValue).\(mode.rawValue)"
    }
}
