//
//  PinnedTileTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// What a pinned series' tile offers before and after the series was started.
@MainActor
struct PinnedTileTests {
    private static let series = SeriesSummary(id: ItemID(rawValue: "freek"), title: "Freeks wilde wereld", artwork: nil)
    private static let season = SeasonID(rawValue: "season-1")

    private let history = ScriptedWatchHistory()
    private let pins = ScriptedPins()

    private func model() -> HomeModel {
        HomeModel(pins: pins,
                  watched: WatchedState(progress: ScriptedProgress(), history: history, later: ScriptedWatchLater()),
                  catalogue: StubCatalogue(),
                  clock: TestClock(),
                  mode: .normal)
    }

    private static func episode(_ name: String) -> Upcoming {
        Upcoming(Playable(id: EpisodeID(rawValue: name), title: name, caption: "Afl. 1 • 10m", synopsis: nil,
                          duration: nil, artwork: nil),
                 in: season)
    }

    @Test("FR-HOME-04: with no episode watched, a pinned series' tile offers its first episode, and plays it")
    func unstartedPinOffersTheFirstEpisode() async throws {
        let first = Self.episode("first")
        await pins.pin(Self.series, startingWith: first, in: .normal)
        let model = model()
        await model.refresh()
        let tile = try #require(model.pinned.first)

        model.select(tile)

        #expect(tile.state == .continues(first, fraction: nil))
        #expect(model.playing?.playable.id == first.id)
        #expect(model.playing?.origin == .series(SeriesPlace(series: Self.series, season: Self.season)))
        #expect(model.path.isEmpty)
    }

    @Test("FR-HOME-04: once a pinned series was started, its tile follows what was watched, not where it started")
    func startedPinFollowsWhatWasWatched() async throws {
        await pins.pin(Self.series, startingWith: Self.episode("first"), in: .normal)
        let third = Self.episode("third")
        await history.record(WatchedEntry(series: Self.series, next: third, playedAt: Date(timeIntervalSince1970: 0)),
                             in: .normal)
        let model = model()

        await model.refresh()

        #expect(try #require(model.pinned.first).state == .continues(third, fraction: nil))
    }

    @Test("FR-HOME-04: a pin whose first episode is not known opens the series' page")
    func pinWithoutAStartOpensThePage() async throws {
        await pins.pin(Self.series, in: .normal)
        let model = model()
        await model.refresh()

        model.select(try #require(model.pinned.first))

        #expect(model.playing == nil)
        #expect(model.path == [.series(Self.series)])
    }
}
