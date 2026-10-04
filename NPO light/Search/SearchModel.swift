//
//  SearchModel.swift
//  NPO light
//

import Foundation
import Observation

/// The search screen's state: what is in the field, and what belongs to it.
///
/// The field is plain state on the main actor and nothing here ever waits on
/// the network before accepting a character (FR-SEARCH-03). What the catalogue
/// answers is only shown while it still belongs to the text in the field.
@MainActor
@Observable
final class SearchModel {
    enum State: Equatable {
        /// Nothing to search for: the field is empty.
        case idle

        /// A search for the text in the field is waiting or under way.
        case searching

        case results(SearchResults)

        /// The catalogue has nothing for this term.
        case noResults(term: String)

        /// The search could not be made. Distinct from having no results.
        case failed
    }

    /// How long the field has to rest before the catalogue is asked, so that a
    /// word typed quickly is one request and not one per letter.
    static let debounce = Duration.milliseconds(300)

    /// The text in the field.
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            search(after: Self.debounce)
        }
    }

    private(set) var state = State.idle

    /// The mode's recent searches, most recent first: what an empty field
    /// shows (FR-SEARCH-04).
    private(set) var recent: [RecentSearch] = []

    /// The search that is waiting or under way, if any.
    private(set) var pending: Task<Void, Never>?

    let mode: Mode

    private let catalogue: any Catalogue
    private let history: any SearchHistory
    private let clock: any Clocking

    init(catalogue: any Catalogue, history: any SearchHistory, clock: any Clocking, mode: Mode) {
        self.catalogue = catalogue
        self.history = history
        self.clock = clock
        self.mode = mode
    }

    /// The text in the field as it is searched for and remembered.
    private var term: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The button on a failed search: ask again for what is in the field.
    func retry() {
        search(after: .zero)
    }

    // MARK: Recent searches

    /// Reads the recent searches, when the page comes on screen.
    func loadRecent() async {
        recent = await history.searches(in: mode)
    }

    /// Something was opened or played from the results: it is kept against
    /// the term in the field (FR-SEARCH-05). Opening a recent search's own
    /// pick, with an empty field, records nothing.
    func chose(_ pick: SearchPick) async {
        await remember(picking: PickedItem(pick))
    }

    /// The page is left. A term that had results and no pick is still
    /// remembered, on its own (FR-SEARCH-05).
    func leave() async {
        guard case .results = state else { return }
        await remember(picking: nil)
    }

    /// A recent term was selected: it goes in the field and is searched for
    /// at once, with no debounce to wait out (FR-SEARCH-06).
    func run(_ search: RecentSearch) {
        query = search.term
        self.search(after: .zero)
    }

    /// Deletes one term and what was picked for it (FR-SEARCH-07).
    func forget(_ search: RecentSearch) async {
        // A history that could not be written is still shown as it is kept.
        try? await history.forget(search.term, in: mode)
        await loadRecent()
    }

    /// Clears this mode's history, after the view has asked (FR-SEARCH-07).
    func clearHistory() async {
        await history.clear(in: mode)
        await loadRecent()
    }

    private func remember(picking pick: PickedItem?) async {
        let term = term
        guard !term.isEmpty else { return }
        try? await history.remember(term, picking: pick, in: mode)
        await loadRecent()
    }

    // MARK: Searching

    private func search(after delay: Duration) {
        // A search for text that is no longer in the field is cancelled, and
        // what it would have shown is never rendered.
        pending?.cancel()
        let term = term
        guard !term.isEmpty else {
            pending = nil
            state = .idle
            return
        }
        state = .searching
        pending = Task {
            await self.run(term, after: delay)
        }
    }

    private func run(_ term: String, after delay: Duration) async {
        let outcome: State
        do {
            try await clock.wait(for: delay)
            let results = try await catalogue.search(for: term, in: mode)
            outcome = results.isEmpty ? .noResults(term: term) : .results(results)
        } catch is CancellationError {
            return
        } catch {
            outcome = .failed
        }
        // A late answer for superseded text is discarded here: the task was
        // cancelled the moment the field changed.
        guard !Task.isCancelled else { return }
        state = outcome
    }
}
