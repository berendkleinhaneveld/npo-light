//
//  LocalDataEraser.swift
//  NPO light
//

import Foundation

/// Erasing what is kept on this television, for one mode or for both
/// (FR-SET-04).
nonisolated protocol LocalDataErasing: Sendable {
    /// Removes the pins, what was watched, the watch later list, the search
    /// history and the positions of each of `modes`, and nothing of a mode
    /// that is not named.
    func erase(_ modes: Set<Mode>) async
}

/// The one place that erases (ADR 0012): every record in `UserDefaults` for
/// the mode, its positions in the store — from both, or an erased position
/// would come back from the copy (ADR 0015, NFR-PRIV-04) — and what the
/// catalogue cache kept of what was browsed in it.
actor LocalDataEraser: LocalDataErasing {
    private let defaults: LocalDefaults
    private let progress: any ProgressKeeping
    private let catalogue: CatalogueCache?

    init(progress: any ProgressKeeping, catalogue: CatalogueCache? = nil, suite: String? = nil) {
        defaults = LocalDefaults(suite: suite)
        self.progress = progress
        self.catalogue = catalogue
    }

    func erase(_ modes: Set<Mode>) async {
        for mode in modes {
            await progress.erase(in: mode)
            // What was browsed in the mode goes with it.
            await catalogue?.erase(mode)
            // Every kind of record, also one added after this was written.
            for record in LocalDefaults.Record.allCases {
                defaults.remove(record, in: mode)
            }
        }
    }
}
