//
//  PlaybackProgress.swift
//  NPO light
//

import Foundation

/// How far something was played, and whether it was finished: two facts
/// that do not depend on each other (ADR 0012).
nonisolated struct PlaybackProgress: Sendable, Equatable, Codable {
    let id: EpisodeID

    /// Where to resume, in seconds. Absent means from the beginning: nothing
    /// was played yet, or it was played to the finish (FR-PLAY-02).
    var offset: TimeInterval?

    /// When it passed the completion threshold. Absent means unfinished. It
    /// stays when the item is played again: watched is not unwatched by
    /// watching (FR-HOME-07).
    var finishedAt: Date?

    /// When this was last written, which is what orders positions by age.
    var updatedAt: Date

    /// How long the item is, when the player knew: what turns the offset
    /// into how far in it is (FR-HOME-06).
    var duration: TimeInterval?

    var isFinished: Bool { finishedAt != nil }

    /// How far in the resume point is, from 0 to 1, when both are known.
    var fraction: Double? {
        guard let offset, let duration, duration > 0 else { return nil }
        return min(1, max(0, offset / duration))
    }
}

/// The one definition of "finished" (FR-PLAY-04): playback passed the later
/// of 95% of the duration and the point where 90 seconds remain.
nonisolated enum Completion {
    static let fraction = 0.95
    static let remainder: TimeInterval = 90

    /// The position from which an item of this duration counts as finished,
    /// or `nil` when the duration is not known: then only reaching the end
    /// finishes it.
    static func finishPoint(of duration: TimeInterval?) -> TimeInterval? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        return max(duration * fraction, duration - remainder)
    }

    static func isFinished(at position: TimeInterval, of duration: TimeInterval?) -> Bool {
        guard let point = finishPoint(of: duration) else { return false }
        return position >= point
    }
}
