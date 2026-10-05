//
//  UnavailableTileTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// Tiles whose item NPO turned out not to have any more.
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
    private let asked = Counter()

    /// A home page over a catalogue that counts what it is asked.
    private func model() -> HomeModel {
        HomeModel(pins: pins,
                  watched: WatchedState(progress: ScriptedProgress(), history: history, later: later),
                  catalogue: StubCatalogue(detail: { [asked] _ in
                      asked.increment()
                      return StubCatalogue.detail
                  }, programme: { [asked] id in
                      asked.increment()
                      return StubCatalogue.film(id)
                  }),
                  clock: TestClock(now: Self.now),
                  mode: .normal)
    }

    private static func playable(_ name: String) -> Playable {
        Playable(id: EpisodeID(rawValue: name), title: name, caption: nil, synopsis: nil, duration: nil, artwork: nil)
    }

    /// What the player was asked for when it said that NPO no longer has it.
    private static func request(_ name: String, _ origin: PlayOrigin = .single) -> PlayRequest {
        PlayRequest(playable: playable(name), origin: origin)
    }

    @Test("ADR 0023: the home page does not ask NPO about its tiles")
    func homeAsksNothing() async {
        await pins.pin(Self.series, in: .normal)
        await later.save(SavedItem(Self.playable("film"), origin: .single), in: .normal)
        let model = model()

        await model.refresh()

        #expect(asked.value == 0)
        #expect(model.later.first?.isUnavailable == false)
    }

    @Test("FR-LATER-11: a saved item that turned out to be gone keeps its tile, shown as unavailable with its title")
    func savedItemThatIsGone() async {
        await later.save(SavedItem(Self.playable("gone"), origin: .single), in: .normal)
        await later.save(SavedItem(Self.playable("there"), origin: .single), in: .normal)
        let model = model()
        await model.refresh()

        await model.playbackEnded(unavailable: Self.request("gone"))

        #expect(model.later.map(\.title) == ["there", "gone"])
        #expect(model.later.map(\.isUnavailable) == [false, true])
        #expect(asked.value == 0)
    }

    @Test("FR-CONTENT-05, FR-LATER-11: selecting an unavailable tile opens the page that explains, and plays nothing")
    func selectingAnUnavailableTile() async throws {
        await later.save(SavedItem(Self.playable("gone"), origin: .single), in: .normal)
        let model = model()
        await model.playbackEnded(unavailable: Self.request("gone"))

        model.select(try #require(model.later.first))

        #expect(model.playing == nil)
        #expect(model.path == [.programme(Self.playable("gone"))])
    }

    @Test("FR-LATER-11: an unavailable item is not taken off the list by the app, and can be by hand")
    func unavailableItemStaysUntilRemoved() async throws {
        await later.save(SavedItem(Self.playable("gone"), origin: .single), in: .normal)
        let model = model()
        await model.playbackEnded(unavailable: Self.request("gone"))
        #expect(await later.saved(in: .normal).count == 1)

        await model.removeSaved(try #require(model.later.first))

        #expect(model.later.isEmpty)
        #expect(await later.saved(in: .normal).isEmpty)
    }

    @Test("FR-CONTENT-05: a recently watched or pinned tile whose episode turned out to be gone says so")
    func recentAndPinnedTiles() async throws {
        let place = PlayOrigin.series(SeriesPlace(series: Self.series, season: Self.season))
        await pins.pin(Self.series, in: .normal)
        await history.record(WatchedEntry(series: Self.series,
                                          next: Upcoming(Self.playable("gone"), in: Self.season),
                                          playedAt: Self.now),
                             in: .normal)
        let model = model()

        await model.playbackEnded(unavailable: Self.request("gone", place))

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

    @Test("FR-CONTENT-05: playback that ended in the ordinary way marks nothing")
    func ordinaryEndMarksNothing() async {
        await later.save(SavedItem(Self.playable("film"), origin: .single), in: .normal)
        let model = model()

        await model.playbackEnded()

        #expect(model.later.first?.isUnavailable == false)
        #expect(model.later.first?.request != nil)
    }
}
