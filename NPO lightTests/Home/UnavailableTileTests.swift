//
//  UnavailableTileTests.swift
//  NPO lightTests
//

import Foundation
import Synchronization
import Testing
@testable import NPO_light

/// Tiles whose item NPO no longer has.
@MainActor
struct UnavailableTileTests {
    nonisolated private static let series = SeriesSummary(id: ItemID(rawValue: "freek"),
                                                          title: "Freeks wilde wereld",
                                                          artwork: nil)
    private static let season = SeasonID(rawValue: "season-1")
    private static let now = Date(timeIntervalSince1970: 10_000_000)

    private let history = ScriptedWatchHistory()
    private let later = ScriptedWatchLater()
    private let pins = ScriptedPins()
    private let clock = TestClock(now: now)

    private func model(_ catalogue: StubCatalogue) -> HomeModel {
        HomeModel(pins: pins,
                  watched: WatchedState(progress: ScriptedProgress(), history: history, later: later),
                  catalogue: catalogue,
                  clock: clock,
                  mode: .normal)
    }

    private static func playable(_ name: String) -> Playable {
        Playable(id: EpisodeID(rawValue: name), title: name, caption: nil, synopsis: nil, duration: nil, artwork: nil)
    }

    /// A catalogue in which the programme called "gone" is gone.
    private static func catalogue(counting asked: Counter = Counter()) -> StubCatalogue {
        StubCatalogue(programme: { id in
            asked.increment()
            if id.rawValue == "gone" { throw BackendError.itemUnavailable }
            return StubCatalogue.film(id)
        })
    }

    private func loaded(_ catalogue: StubCatalogue) async -> HomeModel {
        let model = model(catalogue)
        await model.refresh()
        await model.checking?.value
        return model
    }

    @Test("FR-LATER-11: a saved item NPO no longer has keeps its tile, shown as unavailable with its own title")
    func savedItemThatIsGone() async throws {
        await later.save(SavedItem(Self.playable("gone"), origin: .single), in: .normal)
        await later.save(SavedItem(Self.playable("there"), origin: .single), in: .normal)

        let model = await loaded(Self.catalogue())

        #expect(model.later.map(\.title) == ["there", "gone"])
        #expect(model.later.map(\.isUnavailable) == [false, true])
    }

    @Test("FR-CONTENT-05, FR-LATER-11: selecting an unavailable tile opens the page that explains, and plays nothing")
    func selectingAnUnavailableTile() async throws {
        await later.save(SavedItem(Self.playable("gone"), origin: .single), in: .normal)
        let model = await loaded(Self.catalogue())
        let tile = try #require(model.later.first)

        model.select(tile)

        #expect(model.playing == nil)
        #expect(model.path == [.programme(Self.playable("gone"))])
    }

    @Test("FR-LATER-11: an unavailable item is not taken off the list by the app, and can be by hand")
    func unavailableItemStaysUntilRemoved() async throws {
        await later.save(SavedItem(Self.playable("gone"), origin: .single), in: .normal)
        let model = await loaded(Self.catalogue())
        #expect(await later.saved(in: .normal).count == 1)

        await model.removeSaved(try #require(model.later.first))

        #expect(model.later.isEmpty)
        #expect(await later.saved(in: .normal).isEmpty)
    }

    @Test("FR-CONTENT-05: a recently watched or pinned tile whose episode is gone says so, and can be removed")
    func recentAndPinnedTiles() async throws {
        await pins.pin(Self.series, in: .normal)
        await history.record(WatchedEntry(series: Self.series,
                                          next: Upcoming(Self.playable("gone"), in: Self.season),
                                          playedAt: Self.now),
                             in: .normal)

        let model = await loaded(Self.catalogue())
        #expect(model.pinned.first?.isUnavailable == true)
        #expect(model.continuing.first?.isUnavailable == true)
        // The series' page is where to pick another episode.
        model.select(try #require(model.continuing.first))
        #expect(model.path == [.series(Self.series)])

        await model.unpin(Self.series.id)
        await model.remove(Self.series.id)

        #expect(model.pinned.isEmpty)
        #expect(model.continuing.isEmpty)
    }

    @Test("FR-CONTENT-05: a pinned series NPO no longer has is shown as unavailable")
    func pinnedSeriesThatIsGone() async {
        await pins.pin(Self.series, in: .normal)

        let model = await loaded(StubCatalogue(detail: { _ in throw BackendError.itemUnavailable }))

        #expect(model.pinned.first?.isUnavailable == true)
        #expect(model.pinned.first?.title == "Freeks wilde wereld")
    }

    @Test("NFR-REL-02: a tile NPO could not be asked about is not called unavailable")
    func unknownIsNotUnavailable() async {
        await later.save(SavedItem(Self.playable("film"), origin: .single), in: .normal)

        let model = await loaded(StubCatalogue(programme: { _ in throw BackendError.unreachable }))

        #expect(model.later.first?.isUnavailable == false)
        #expect(model.later.first?.request != nil)
    }

    @Test("NFR-PERF-03: NPO is asked about a tile once, and again only when the answer has aged")
    func answersAreKept() async {
        await later.save(SavedItem(Self.playable("film"), origin: .single), in: .normal)
        let asked = Counter()
        let model = await loaded(Self.catalogue(counting: asked))
        #expect(asked.value == 1)

        await model.refresh()
        await model.checking?.value
        #expect(asked.value == 1)

        clock.advance(by: .seconds(HomeModel.availabilityAge))
        await model.refresh()
        await model.checking?.value

        #expect(asked.value == 2)
    }

    @Test("FR-CONTENT-06: a programme NPO will not let this account play is unavailable too")
    func unplayableIsUnavailable() async {
        await later.save(SavedItem(Self.playable("film"), origin: .single), in: .normal)
        let refused = StubCatalogue(programme: { id in
            ProgrammeDetail(playable: StubCatalogue.film(id).playable, isPlayable: false)
        })

        let model = await loaded(refused)

        #expect(model.later.first?.isUnavailable == true)
    }
}
