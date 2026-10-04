//
//  ProgrammeDetailModel.swift
//  NPO light
//

import Foundation
import Observation

/// The page of a programme that belongs to no series — a film, a one-off
/// documentary: what it is, playing or resuming it, and saving it for later
/// (FR-CONTENT-03). It is never pinned (FR-HOME-03).
@MainActor
@Observable
final class ProgrammeDetailModel {
    enum Page: Equatable {
        case loading
        case loaded(ProgrammeDetail)

        /// NPO no longer has it (FR-CONTENT-05).
        case unavailable

        /// It could not be fetched; trying again may help.
        case failed
    }

    /// What the list that led here already knew, shown while the rest loads.
    let summary: Playable
    let mode: Mode

    private(set) var page = Page.loading

    /// Whether it is on this mode's watch later list (FR-LATER-03).
    private(set) var isSaved = false

    private var position: PlaybackProgress?

    private let catalogue: any Catalogue
    private let watched: WatchedState

    init(summary: Playable, catalogue: any Catalogue, watched: WatchedState, mode: Mode) {
        self.summary = summary
        self.catalogue = catalogue
        self.watched = watched
        self.mode = mode
    }

    /// It has a position to carry on from: the action reads *Verder kijken*.
    var resumes: Bool {
        position?.offset != nil
    }

    var isWatched: Bool {
        position?.isFinished == true
    }

    /// What the main action plays, once NPO has said that it can be played
    /// (FR-CONTENT-06).
    var request: PlayRequest? {
        guard case .loaded(let detail) = page, detail.isPlayable else { return nil }
        return PlayRequest(playable: detail.playable, origin: .single)
    }

    func load() async {
        page = .loading
        await readWatched()
        do {
            page = .loaded(try await catalogue.programme(summary.id, in: mode))
        } catch BackendError.itemUnavailable {
            page = .unavailable
        } catch is CancellationError {
            // The page went away.
        } catch {
            page = .failed
        }
    }

    /// Reads what was watched and saved as it is kept now: when the page
    /// opens, and again when the player closes (FR-HOME-10).
    func readWatched() async {
        position = await watched.progress.progress(of: summary.id, in: mode)
        isSaved = await watched.later.saved(in: mode).contains { $0.id == summary.id }
    }

    /// Saves it for later, or takes it off the list (FR-LATER-03,
    /// FR-LATER-09). It is saved as NPO now describes it, when the page has
    /// that.
    func toggleSave() async {
        // A list that could not be written is shown as it is kept.
        if isSaved {
            try? await watched.later.remove(summary.id, in: mode)
        } else {
            var current = summary
            if case .loaded(let detail) = page { current = detail.playable }
            try? await watched.later.save(SavedItem(current, origin: .single), in: mode)
        }
        await readWatched()
    }
}

#if DEBUG
extension ProgrammeDetailModel {
    /// A programme's page over the scripted catalogue, for previews.
    static func scripted(_ summary: Playable) -> ProgrammeDetailModel {
        ProgrammeDetailModel(summary: summary, catalogue: ScriptedCatalogue(), watched: .scripted(), mode: .normal)
    }
}
#endif
