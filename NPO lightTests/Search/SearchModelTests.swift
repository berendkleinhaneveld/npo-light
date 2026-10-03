//
//  SearchModelTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

@MainActor
struct SearchModelTests {
    nonisolated private static func results(_ title: String) -> SearchResults {
        SearchResults(series: [SeriesSummary(id: ItemID(rawValue: title), title: title, artwork: nil)],
                      playables: [])
    }

    private func model(_ catalogue: StubCatalogue,
                       clock: TestClock = TestClock(),
                       mode: Mode = .normal) -> SearchModel {
        SearchModel(catalogue: catalogue, clock: clock, mode: mode)
    }

    @Test("FR-SEARCH-02: typing shows the results for what is in the field, with no button to press")
    func typingShowsResults() async {
        let catalogue = StubCatalogue()
        let model = model(catalogue)
        #expect(model.state == .idle)

        model.query = "fr"
        #expect(model.state == .searching)
        await model.pending?.value

        #expect(model.state == .results(StubCatalogue.results))
        #expect(catalogue.searches == [StubCatalogue.Search(query: "fr", mode: .normal)])
    }

    @Test("FR-SEARCH-02: typing more and deleting again each search for the text as it then is")
    func resultsFollowTheField() async {
        let catalogue = StubCatalogue(answer: { Self.results($0) })
        let model = model(catalogue)

        model.query = "fr"
        await model.pending?.value
        model.query = "free"
        await model.pending?.value
        #expect(model.state == .results(Self.results("free")))

        model.query = "fr"
        await model.pending?.value

        #expect(model.state == .results(Self.results("fr")))
    }

    @Test("FR-SEARCH-03: a word typed quickly is one request, after the field has rested")
    func quickTypingIsOneRequest() async {
        let catalogue = StubCatalogue()
        let clock = TestClock()
        let model = model(catalogue, clock: clock)

        model.query = "f"
        model.query = "fr"
        model.query = "fre"
        await model.pending?.value

        #expect(catalogue.searches.map(\.query) == ["fre"])
        #expect(clock.waits == [SearchModel.debounce])
    }

    @Test("FR-SEARCH-03: with a backend that never answers, the field keeps accepting input")
    func silentBackendDoesNotBlockTyping() async {
        let never = Gate()
        let model = model(StubCatalogue(answer: { _ in
            await never.wait()
            return .empty
        }))

        model.query = "f"
        let first = model.pending
        await Task.yield()
        model.query = "fr"
        model.query = "fre"

        #expect(model.query == "fre")
        #expect(model.state == .searching)
        #expect(first?.isCancelled == true)
    }

    @Test("FR-SEARCH-03: a late answer for superseded text is discarded, never rendered")
    func lateAnswerIsDiscarded() async {
        let reached = Gate()
        let release = Gate()
        let catalogue = StubCatalogue(answer: { query in
            if query == "fr" {
                reached.open()
                await release.wait()
            }
            return Self.results(query)
        })
        let model = model(catalogue)

        model.query = "fr"
        let superseded = model.pending
        await reached.wait()
        model.query = "freek"
        await model.pending?.value
        #expect(model.state == .results(Self.results("freek")))

        release.open()
        await superseded?.value

        #expect(model.state == .results(Self.results("freek")))
    }

    @Test("FR-SEARCH-03: clearing the field asks nothing and shows nothing stale")
    func clearingTheFieldGoesIdle() async {
        let catalogue = StubCatalogue()
        let model = model(catalogue)
        model.query = "fr"
        await model.pending?.value

        model.query = "  "

        #expect(model.state == .idle)
        #expect(model.pending == nil)
        #expect(catalogue.searches.count == 1)
    }

    @Test("FR-SEARCH-08, FR-MODE-04: a search in kids mode asks the kids catalogue")
    func kidsModeSearchesAsKids() async {
        let catalogue = StubCatalogue()
        let model = model(catalogue, mode: .kids)

        model.query = "fr"
        await model.pending?.value

        #expect(catalogue.searches == [StubCatalogue.Search(query: "fr", mode: .kids)])
    }

    @Test("FR-SEARCH-09: a search that matches nothing names the term that was searched")
    func noResultsNamesTheTerm() async {
        let model = model(StubCatalogue(answer: { _ in .empty }))

        model.query = " qqq "
        await model.pending?.value

        #expect(model.state == .noResults(term: "qqq"))
        #expect(model.query == " qqq ")
    }

    @Test("FR-SEARCH-09: a failed search is distinct from no results, and a retry works in place")
    func failedSearchCanBeRetried() async {
        let attempts = Counter()
        let catalogue = StubCatalogue(answer: { _ in
            if attempts.increment() == 1 { throw BackendError.unreachable }
            return StubCatalogue.results
        })
        let clock = TestClock()
        let model = model(catalogue, clock: clock)

        model.query = "fr"
        await model.pending?.value
        #expect(model.state == .failed)
        #expect(model.query == "fr")

        model.retry()
        await model.pending?.value

        #expect(model.state == .results(StubCatalogue.results))
        #expect(clock.waits == [SearchModel.debounce, .zero])
    }
}
