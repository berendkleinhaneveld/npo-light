//
//  StoredProgress.swift
//  NPO light
//

import Foundation
import SwiftData

/// A playback position as the store keeps it: the app's one `@Model`
/// (ADR 0015). Nothing outside ``ProgressStore`` sees one; what leaves the
/// store is a ``PlaybackProgress``.
///
/// The mode is a column (ADR 0012), and the two together are what a position
/// is looked up by, so they are indexed: this table has no upper bound
/// (ADR 0006).
@Model
nonisolated final class StoredProgress {
    #Unique<StoredProgress>([\.mode, \.episode])
    #Index<StoredProgress>([\.mode, \.episode])

    var mode: String
    var episode: String
    var offset: Double?
    var finishedAt: Date?
    var updatedAt: Date

    init(_ progress: PlaybackProgress, mode: Mode) {
        self.mode = mode.rawValue
        episode = progress.id.rawValue
        offset = progress.offset
        finishedAt = progress.finishedAt
        updatedAt = progress.updatedAt
    }

    var progress: PlaybackProgress {
        PlaybackProgress(id: EpisodeID(rawValue: episode),
                         offset: offset,
                         finishedAt: finishedAt,
                         updatedAt: updatedAt)
    }

    func take(_ progress: PlaybackProgress) {
        offset = progress.offset
        finishedAt = progress.finishedAt
        updatedAt = progress.updatedAt
    }
}
