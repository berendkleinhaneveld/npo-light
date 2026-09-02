//
//  Fixture.swift
//  NPO lightTests
//

import Foundation

/// Loads a captured response body from the test bundle (ADR 0009).
///
/// See `Fixtures/README.md` for where they come from and what may be added.
nonisolated enum Fixture {
    /// The bytes of `Fixtures/<name>.json`.
    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: FixtureAnchor.self)
        // Xcode's synchronised groups may flatten the directory into the bundle
        // root, so the subdirectory is a preference rather than a promise.
        let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: "json")
        guard let url else {
            throw FixtureError.notInBundle(name)
        }
        return try Data(contentsOf: url)
    }

    /// `Fixtures/<name>.json` as a dictionary, for assertions about shape.
    static func json(_ name: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: try data(name))
        guard let dictionary = object as? [String: Any] else {
            throw FixtureError.notAnObject(name)
        }
        return dictionary
    }
}

nonisolated enum FixtureError: Error, Equatable {
    case notInBundle(String)
    case notAnObject(String)
}

/// Only here to name the test bundle for `Bundle(for:)`.
private final class FixtureAnchor {}
