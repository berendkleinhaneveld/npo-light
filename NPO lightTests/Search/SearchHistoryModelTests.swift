//
//  SearchHistoryModelTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// The search screen's use of the history: what it remembers, and when.
@MainActor
struct SearchHistoryModelTests {
    private static let series = StubCatalogue.results.series[0]
    private static let picked = PickedItem(.series(series))

    private let history = ScriptedSearchHistory()
    private let catalogue = StubCatalogue()
    private let clock = TestClock()

    private func model(mode: Mode = .normal) -> SearchModel {
        SearchModel(catalogue: catalogue, history: history, clock: clock, mode: mode)
    }

    /// A model with `text` typed and its results on screen.
    private func searched(_ text: String) async -> SearchModel {
        let model = model()
        model.query = text
        await model.pending?.value
        return model
    }

    @Test("FR-SEARCH-04: an empty field shows the recent terms, most recent first")
    func emptyFieldShowsRecentTerms() async {
        await history.remember("klokhuis", picking: nil, in: .normal)
        await history.remember("fr", picking: nil, in: .normal)
        let model = model()
        #expect(model.recent.isEmpty)

        await model.loadRecent()

        #expect(model.state == .idle)
        #expect(model.recent.map(\.term) == ["fr", "klokhuis"])
    }

    @Test("FR-SEARCH-04: clearing the field returns to the recent terms")
    func clearingReturnsToRecentTerms() async {
        let model = await searched("fr")
        await model.chose(.series(Self.series))

        model.query = ""

        #expect(model.state == .idle)
        #expect(model.recent.map(\.term) == ["fr"])
    }

    @Test("FR-SEARCH-05: what is picked is kept against the exact term in the field")
    func pickIsKeptAgainstTheTerm() async {
        let model = await searched(" fr ")

        await model.chose(.series(Self.series))

        let expected = [RecentSearch(term: "fr", picks: [Self.picked])]
        #expect(model.recent == expected)
        #expect(await history.searches(in: .normal) == expected)
    }

    @Test("FR-SEARCH-05: an episode that is played is kept as that episode")
    func playedEpisodeIsKept() async {
        let episode = StubCatalogue.episodes(of: SeasonID(rawValue: "season-1"))[0]
        let model = await searched("fr")

        await model.chose(.playable(episode))

        let pick = try? #require(model.recent.first?.picks.first)
        #expect(pick?.kind == .playable)
        #expect(pick?.identifier == episode.id.rawValue)
        #expect(pick?.caption == episode.caption)
    }

    @Test("FR-SEARCH-05: a term with results and no pick is remembered on leaving, as a term on its own")
    func termWithoutPickIsRemembered() async {
        let model = await searched("fr")

        await model.leave()

        #expect(model.recent == [RecentSearch(term: "fr", picks: [])])
    }

    @Test("FR-SEARCH-05: leaving after a pick keeps the pick")
    func leavingKeepsThePick() async {
        let model = await searched("fr")
        await model.chose(.series(Self.series))

        await model.leave()

        #expect(model.recent == [RecentSearch(term: "fr", picks: [Self.picked])])
    }

    @Test("FR-SEARCH-05: a term that found nothing, or was never answered, is not remembered")
    func termWithoutResultsIsNotRemembered() async {
        let nothing = SearchModel(catalogue: StubCatalogue(answer: { _ in .empty }),
                                  history: history,
                                  clock: clock,
                                  mode: .normal)
        nothing.query = "qqq"
        await nothing.pending?.value
        await nothing.leave()

        let unanswered = model()
        unanswered.query = "fr"
        await unanswered.leave()

        let empty = model()
        await empty.leave()

        #expect(await history.searches(in: .normal).isEmpty)
    }

    @Test("FR-SEARCH-06: selecting a recent term puts it in the field and searches at once")
    func recentTermRunsTheSearch() async {
        await history.remember("fr", picking: Self.picked, in: .normal)
        let model = model()
        await model.loadRecent()
        let recent = model.recent[0]

        model.run(recent)
        #expect(model.query == "fr")
        #expect(model.state == .searching)
        await model.pending?.value

        #expect(model.state == .results(StubCatalogue.results))
        #expect(catalogue.searches.map(\.query) == ["fr"])
        // No debounce to wait out: nobody is typing.
        #expect(clock.waits == [.zero])
    }

    @Test("FR-SEARCH-06: a picked item opens as what it was, without a search")
    func pickedItemOpensDirectly() async {
        let episode = StubCatalogue.episodes(of: SeasonID(rawValue: "season-1"))[0]

        #expect(PickedItem(.series(Self.series)).pick == .series(Self.series))
        #expect(PickedItem(.playable(episode)).pick == .playable(episode))
        #expect(catalogue.searches.isEmpty)
    }

    @Test("FR-SEARCH-06: opening a recent search's pick, with an empty field, records nothing new")
    func openingAPickRecordsNothing() async {
        await history.remember("fr", picking: Self.picked, in: .normal)
        let model = model()
        await model.loadRecent()

        await model.chose(Self.picked.pick)

        #expect(model.recent == [RecentSearch(term: "fr", picks: [Self.picked])])
    }

    @Test("FR-SEARCH-07: deleting a term removes it and what was picked for it")
    func deletingATermRemovesIt() async {
        await history.remember("klokhuis", picking: nil, in: .normal)
        await history.remember("fr", picking: Self.picked, in: .normal)
        let model = model()
        await model.loadRecent()

        await model.forget(model.recent[0])

        #expect(model.recent == [RecentSearch(term: "klokhuis", picks: [])])
        #expect(await history.searches(in: .normal).map(\.term) == ["klokhuis"])
    }

    @Test("FR-SEARCH-07, FR-MODE-05: clearing the history in one mode leaves the other mode's alone")
    func clearingIsPerMode() async {
        await history.remember("fr", picking: nil, in: .normal)
        await history.remember("bram", picking: nil, in: .kids)
        let model = model(mode: .kids)
        await model.loadRecent()
        #expect(model.recent.map(\.term) == ["bram"])

        await model.clearHistory()

        #expect(model.recent.isEmpty)
        #expect(await history.searches(in: .kids).isEmpty)
        #expect(await history.searches(in: .normal).map(\.term) == ["fr"])
    }
}
