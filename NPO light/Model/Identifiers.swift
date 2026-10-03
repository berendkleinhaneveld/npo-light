//
//  Identifiers.swift
//  NPO light
//

import Foundation

/// The app's own name for an item: a series, a film or a standalone episode.
///
/// Opaque above the NPO boundary (ADR 0012). It is what pins, history and
/// search picks store, so it has to stay the same across launches
/// (FR-CONTENT-01).
nonisolated struct ItemID: Hashable, Sendable, Codable {
    let rawValue: String
}

/// The app's own name for something that can be played: a film or one episode.
nonisolated struct EpisodeID: Hashable, Sendable, Codable {
    let rawValue: String
}

/// One season of a series.
nonisolated struct SeasonID: Hashable, Sendable, Codable {
    let rawValue: String
}
