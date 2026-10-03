//
//  Mode.swift
//  NPO light
//

import Foundation

/// The app is always in exactly one of these (FR-MODE-01).
nonisolated enum Mode: String, Sendable, CaseIterable, Codable {
    case normal
    case kids
}
