//
//  HomeModelTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

@MainActor
struct HomeModelTests {
    private static let freek = SeriesSummary(id: ItemID(rawValue: "freek"), title: "Freeks wilde wereld", artwork: nil)
    private static let klokhuis = SeriesSummary(id: ItemID(rawValue: "klokhuis"), title: "Het Klokhuis", artwork: nil)

    @Test("FR-HOME-02: the pinned row shows the pins, most recently pinned first")
    func pinnedRowShowsThePins() async {
        let model = HomeModel(pins: ScriptedPins([Self.klokhuis, Self.freek]), mode: .normal)
        #expect(model.pinned.isEmpty)

        await model.refresh()

        #expect(model.pinned.map(\.id) == [Self.klokhuis.id, Self.freek.id])
    }

    @Test("FR-HOME-09: with nothing pinned the row is empty, for the page to explain")
    func nothingPinnedIsEmpty() async {
        let model = HomeModel(pins: ScriptedPins(), mode: .normal)

        await model.refresh()

        #expect(model.pinned.isEmpty)
    }

    @Test("FR-HOME-10: a series pinned on its own page is on the row when home comes back")
    func pinMadeElsewhereShowsOnReturn() async {
        let pins = ScriptedPins()
        let model = HomeModel(pins: pins, mode: .normal)
        await model.refresh()
        model.open(Self.freek)
        #expect(model.path == [.series(Self.freek)])

        await pins.pin(Self.freek, in: .normal)
        model.path.removeAll()
        await model.refresh()

        #expect(model.pinned.map(\.id) == [Self.freek.id])
    }

    @Test("FR-HOME-05: unpinning from home removes the tile at once, without leaving the page")
    func unpinningFromHome() async {
        let pins = ScriptedPins([Self.klokhuis, Self.freek])
        let model = HomeModel(pins: pins, mode: .normal)
        await model.refresh()

        await model.unpin(Self.klokhuis.id)

        #expect(model.pinned.map(\.id) == [Self.freek.id])
        #expect(model.path.isEmpty)
        #expect(await pins.pinned(in: .normal) == [Self.freek])
    }

    @Test("FR-MODE-05: the home page shows its own mode's pins only")
    func pinsOfTheOtherModeAreNotShown() async {
        let pins = ScriptedPins([Self.freek], in: .kids)
        let normal = HomeModel(pins: pins, mode: .normal)
        let kids = HomeModel(pins: pins, mode: .kids)

        await normal.refresh()
        await kids.refresh()

        #expect(normal.pinned.isEmpty)
        #expect(kids.pinned.map(\.id) == [Self.freek.id])
    }

    @Test("FR-SEARCH-01: search is one action from home, and a picked series opens its page")
    func searchAndSeriesAreOnTheStack() {
        let model = HomeModel(pins: ScriptedPins(), mode: .normal)

        model.openSearch()
        model.open(.series(Self.freek))

        #expect(model.path == [.search, .series(Self.freek)])
        #expect(model.playing == nil)
    }

    @Test("FR-HOME-10: a tile taken off a row leaves focus to the one after it, or the one before the last")
    func removedTileHasAnHeir() {
        let tiles = ["a", "b", "c"].map { name in
            HomeTile(pinned: SeriesSummary(id: ItemID(rawValue: name), title: name, artwork: nil), startingWith: nil)
        }
        let first = tiles[0].id
        let last = tiles[tiles.count - 1].id

        #expect(tiles.neighbour(of: first) == tiles[1].id)
        #expect(tiles.neighbour(of: last) == tiles[tiles.count - 2].id)
        // The only one: focus goes to the way to search.
        #expect([tiles[0]].neighbour(of: first) == nil)
    }
}
