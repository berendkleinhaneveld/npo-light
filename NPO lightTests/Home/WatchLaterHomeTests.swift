//
//  WatchLaterHomeTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// The watch later row, and saving from the home page and from search.
@MainActor
struct WatchLaterHomeTests {
    private static let now = Date(timeIntervalSince1970: 10_000_000)
    nonisolated private static let series = SeriesSummary(id: ItemID(rawValue: "freek"),
                                                          title: "Freeks wilde wereld",
                                                          artwork: nil)
    nonisolated private static let season = SeasonID(rawValue: "season-1")
    private static let place = PlayOrigin.series(SeriesPlace(series: series, season: season))

    private let progress = ScriptedProgress()
    private let history = ScriptedWatchHistory()
    private let later = ScriptedWatchLater()
    private let pins = ScriptedPins()

    private func model(in mode: Mode = .normal) -> HomeModel {
        HomeModel(pins: pins,
                  watched: WatchedState(progress: progress, history: history, later: later),
                  catalogue: StubCatalogue(place: { episode in
                      episode.rawValue == "placed" ? SeriesPlace(series: Self.series, season: Self.season) : nil
                  }),
                  clock: TestClock(now: Self.now),
                  mode: mode)
    }

    private static func playable(_ name: String) -> Playable {
        Playable(id: EpisodeID(rawValue: name), title: name, caption: "Afl. 1 • 10m", synopsis: nil, duration: nil,
                 artwork: nil)
    }

    @Test("FR-LATER-05: with nothing saved there is no row, and saving the first item makes it appear")
    func rowAppearsWithTheFirstItem() async {
        let model = model()
        await model.refresh()
        #expect(model.later.isEmpty)

        await model.toggleSave(Self.playable("film"), origin: .single)

        #expect(model.later.map(\.title) == ["film"])
        #expect(model.saved == [EpisodeID(rawValue: "film")])
    }

    @Test("FR-LATER-03: the action saves what is not saved and removes what is")
    func savingToggles() async {
        let model = model()
        await model.toggleSave(Self.playable("film"), origin: .single)

        await model.toggleSave(Self.playable("film"), origin: .single)

        #expect(model.later.isEmpty)
        #expect(model.saved.isEmpty)
        #expect(await later.saved(in: .normal).isEmpty)
    }

    @Test("FR-LATER-04: the row is most recently saved first")
    func mostRecentlySavedFirst() async {
        let model = model()

        await model.toggleSave(Self.playable("first"), origin: .single)
        await model.toggleSave(Self.playable("second"), origin: .single)

        #expect(model.later.map(\.title) == ["second", "first"])
    }

    @Test("FR-LATER-05: an episode's tile says which series it is of")
    func episodeTileNamesItsSeries() async throws {
        let model = model()

        await model.toggleSave(Self.playable("aflevering"), origin: Self.place)

        let tile = try #require(model.later.first)
        #expect(tile.title == "Freeks wilde wereld")
        #expect(tile.series == Self.series)
        guard case .continues(let episode, _) = tile.state else {
            Issue.record("The tile does not name an episode")
            return
        }
        #expect(episode.title == "aflevering")
    }

    @Test("FR-LATER-12: a tile plays that exact item, and says what is known about it")
    func tilePlaysTheSavedItem() async throws {
        let model = model()
        await model.toggleSave(Self.playable("aflevering"), origin: Self.place)

        model.select(try #require(model.later.first))

        #expect(model.playing?.playable.id == EpisodeID(rawValue: "aflevering"))
        #expect(model.playing?.origin == Self.place)
        #expect(model.path.isEmpty)
    }

    @Test("FR-LATER-08: a saved item that was started stays on the list, with its progress")
    func startedItemStays() async throws {
        let film = Self.playable("film")
        await later.save(SavedItem(film, origin: .single), in: .normal)
        await history.record(WatchedEntry(single: film, playedAt: Self.now), in: .normal)
        await progress.keep(PlaybackProgress(id: film.id, offset: 300, finishedAt: nil, updatedAt: Self.now,
                                             duration: 600),
                            in: .normal)
        let model = model()

        await model.refresh()

        let saved = try #require(model.later.first)
        let recent = try #require(model.continuing.first)
        #expect(saved.state == recent.state)
        #expect(saved.state == .continues(Upcoming(film, in: nil), fraction: 0.5))
    }

    @Test("FR-LATER-08: removing it from Kijk verder leaves it on the watch later list")
    func removingFromTheRowKeepsItSaved() async {
        let film = Self.playable("film")
        await later.save(SavedItem(film, origin: .single), in: .normal)
        await history.record(WatchedEntry(single: film, playedAt: Self.now), in: .normal)
        let model = model()
        await model.refresh()

        await model.remove(ItemID(rawValue: "film"))

        #expect(model.continuing.isEmpty)
        #expect(model.later.count == 1)
    }

    @Test("FR-LATER-03: something on Kijk verder can be saved from its tile")
    func savingFromARecentTile() async throws {
        let episode = Self.playable("aflevering")
        await history.record(WatchedEntry(series: Self.series, next: Upcoming(episode, in: Self.season),
                                          playedAt: Self.now),
                             in: .normal)
        let model = model()
        await model.refresh()

        await model.toggleSave(try #require(model.continuing.first))

        #expect(await later.saved(in: .normal) == [SavedItem(episode.kept, origin: Self.place)])
        #expect(model.saved.contains(episode.id))
    }

    @Test("FR-LATER-09: removing from the row takes the tile away at once, and keeps where it was watched to")
    func removingByHand() async throws {
        let film = Self.playable("film")
        await later.save(SavedItem(film, origin: .single), in: .normal)
        await progress.keep(PlaybackProgress(id: film.id, offset: 300, finishedAt: nil, updatedAt: Self.now),
                            in: .normal)
        let model = model()
        await model.refresh()

        await model.removeSaved(try #require(model.later.first))

        #expect(model.later.isEmpty)
        #expect(model.path.isEmpty)
        #expect(await progress.progress(of: film.id, in: .normal)?.offset == 300)
    }

    @Test("FR-LATER-01: saving does not pin, and what is pinned is not saved")
    func savingIsNotPinning() async {
        await pins.pin(Self.series, in: .normal)
        let model = model()

        await model.toggleSave(Self.playable("aflevering"), origin: Self.place)

        #expect(model.pinned.count == 1)
        #expect(model.later.count == 1)
        #expect(await pins.pinned(in: .normal) == [Self.series])
    }

    @Test("FR-LATER-10: each mode shows its own list")
    func listsArePerMode() async {
        await later.save(SavedItem(Self.playable("film"), origin: .single), in: .kids)
        let normal = model()
        let kids = model(in: .kids)

        await normal.refresh()
        await kids.refresh()

        #expect(normal.later.isEmpty)
        #expect(normal.saved.isEmpty)
        #expect(kids.later.count == 1)
    }

    @Test("FR-CONTENT-03: an episode in a list opens the series it belongs to, which NPO is asked for")
    func episodeOpensItsSeries() async {
        let model = model()
        model.openSearch()

        await model.openSeries(of: Self.playable("placed"))
        #expect(model.path == [.search, .series(Self.series)])

        // One NPO cannot place opens nothing.
        await model.openSeries(of: Self.playable("lost"))

        #expect(model.path == [.search, .series(Self.series)])
    }
}

nonisolated extension Playable {
    /// As it is after being kept: without what a tile does not need.
    var kept: Playable {
        Playable(id: id, title: title, caption: caption, synopsis: nil, duration: nil, artwork: artwork)
    }
}
