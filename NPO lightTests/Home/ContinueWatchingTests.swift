//
//  ContinueWatchingTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// The *Kijk verder* row and the pinned tiles, as the home page works them
/// out from what is kept.
@MainActor
struct ContinueWatchingTests {
    private static let now = Date(timeIntervalSince1970: 10_000_000)
    private static let day: TimeInterval = 24 * 60 * 60
    private static let season = SeasonID(rawValue: "season-1")

    private let progress = ScriptedProgress()
    private let history = ScriptedWatchHistory()
    private let pins = ScriptedPins()

    private func model(in mode: Mode = .normal) -> HomeModel {
        HomeModel(pins: pins,
                  watched: WatchedState(progress: progress, history: history),
                  clock: TestClock(now: Self.now),
                  mode: mode)
    }

    private static func series(_ name: String) -> SeriesSummary {
        SeriesSummary(id: ItemID(rawValue: name), title: name, artwork: nil)
    }

    private static func episode(_ name: String) -> Playable {
        Playable(id: EpisodeID(rawValue: name), title: name, caption: "Afl. 1 • 10m", synopsis: nil, duration: nil,
                 artwork: URL(string: "https://assets.example/\(name).jpg"))
    }

    /// A series that continues with an episode named after it, played
    /// `ago` seconds ago.
    private static func live(_ name: String, played ago: TimeInterval = 0) -> WatchedEntry {
        WatchedEntry(series: series(name),
                     next: Upcoming(episode("\(name)-next"), in: season),
                     playedAt: now.addingTimeInterval(-ago))
    }

    private static func finished(_ name: String, ago: TimeInterval) -> WatchedEntry {
        var entry = WatchedEntry(series: series(name), next: nil, playedAt: now.addingTimeInterval(-ago))
        entry.finishedAt = now.addingTimeInterval(-ago)
        return entry
    }

    /// What stopping `id` at two and a half minutes leaves.
    private func stopped(_ id: EpisodeID, of duration: TimeInterval?) async {
        await progress.keep(PlaybackProgress(id: id,
                                             offset: 150,
                                             finishedAt: nil,
                                             updatedAt: Self.now,
                                             duration: duration),
                            in: .normal)
    }

    // MARK: The rules of the row

    @Test("FR-HOME-06: the row is what was played, most recently played first")
    func mostRecentlyPlayedFirst() {
        let entries = [Self.live("older", played: 300), Self.live("newest"), Self.live("oldest", played: 900)]

        let row = ContinueWatching.row(from: entries, at: Self.now)

        #expect(row.map(\.title) == ["newest", "older", "oldest"])
    }

    @Test("FR-HOME-06: the twenty-first item pushes out the twentieth, and only that one")
    func capIsTwenty() {
        #expect(ContinueWatching.cap == 20)
        let entries = (1...21).map { Self.live("series-\($0)", played: TimeInterval($0)) }

        let row = ContinueWatching.row(from: entries, at: Self.now)

        #expect(row.map(\.title) == (1...20).map { "series-\($0)" })
    }

    @Test("FR-HOME-06: no unfinished entry is dropped for its age")
    func unfinishedDoesNotExpire() {
        let row = ContinueWatching.row(from: [Self.live("old film", played: 400 * Self.day)], at: Self.now)

        #expect(row.map(\.title) == ["old film"])
    }

    @Test("FR-HOME-07: an item with nothing left to watch stays seven days, then leaves")
    func finishedStaysSevenDays() {
        #expect(ContinueWatching.finishedStays == 7 * Self.day)
        let entries = [Self.finished("yesterday", ago: Self.day),
                       Self.finished("almost", ago: 7 * Self.day - 1),
                       Self.finished("gone", ago: 7 * Self.day)]

        let row = ContinueWatching.row(from: entries, at: Self.now)

        #expect(row.map(\.title) == ["yesterday", "almost"])
    }

    @Test("FR-HOME-07: a finish in the future, from a clock that was moved back, counts as finished now")
    func futureFinishIsShown() {
        let row = ContinueWatching.row(from: [Self.finished("ahead", ago: -30 * Self.day)], at: Self.now)

        #expect(row.count == 1)
    }

    @Test("FR-HOME-06, FR-HOME-07: a finished item still on its seven days takes a slot like any other")
    func finishedTakesASlot() {
        let entries = [Self.finished("done", ago: 0)]
            + (1...20).map { Self.live("series-\($0)", played: TimeInterval($0)) }

        let row = ContinueWatching.row(from: entries, at: Self.now)

        #expect(row.first?.title == "done")
        #expect(row.last?.title == "series-19")
    }

    @Test("FR-HOME-08: an item taken off the row does not take one of the twenty slots")
    func hiddenTakesNoSlot() {
        var hidden = Self.live("hidden")
        hidden.isHidden = true
        let entries = [hidden] + (1...20).map { Self.live("series-\($0)", played: TimeInterval($0)) }

        let row = ContinueWatching.row(from: entries, at: Self.now)

        #expect(row.count == 20)
        #expect(!row.contains { $0.title == "hidden" })
    }

    // MARK: The home page

    @Test("FR-HOME-06: a tile is the episode to continue with, and shows how far in it is")
    func tileShowsTheEpisodeAndProgress() async throws {
        let entry = Self.live("freek")
        await history.record(entry, in: .normal)
        let next = try #require(entry.next)
        await stopped(next.id, of: 600)
        let model = model()

        await model.refresh()

        let tile = try #require(model.continuing.first)
        #expect(tile.title == "freek")
        #expect(tile.state == .continues(next, fraction: 0.25))
        #expect(tile.artwork == next.artwork)
    }

    @Test("FR-HOME-07: after a finished episode the tile offers the next one, with no progress shown")
    func nextEpisodeShowsNoProgress() async throws {
        await history.record(Self.live("freek"), in: .normal)
        let model = model()

        await model.refresh()

        guard case .continues(_, let fraction) = try #require(model.continuing.first).state else {
            Issue.record("The tile does not continue with an episode")
            return
        }
        #expect(fraction == nil)
    }

    @Test("FR-HOME-04, FR-PLAY-09: selecting a tile plays the episode it names, and says which series it is of")
    func selectingATilePlays() async throws {
        let entry = Self.live("freek")
        await history.record(entry, in: .normal)
        let model = model()
        await model.refresh()

        model.select(try #require(model.continuing.first))

        #expect(model.playing?.playable.id == entry.next?.id)
        #expect(model.playing?.origin == .series(SeriesPlace(series: Self.series("freek"), season: Self.season)))
        #expect(model.path.isEmpty)
    }

    @Test("FR-HOME-07: selecting a finished tile opens the series' page instead of replaying it")
    func finishedTileOpensThePage() async throws {
        await history.record(Self.finished("freek", ago: Self.day), in: .normal)
        let model = model()
        await model.refresh()
        let tile = try #require(model.continuing.first)
        #expect(tile.state == .finished)

        model.select(tile)

        #expect(model.playing == nil)
        #expect(model.path == [.series(Self.series("freek"))])
    }

    @Test("FR-HOME-04: a pinned series nobody started opens its page")
    func unstartedPinOpensThePage() async throws {
        await pins.pin(Self.series("freek"), in: .normal)
        let model = model()
        await model.refresh()
        let tile = try #require(model.pinned.first)
        #expect(tile.state == .notStarted)

        model.select(tile)

        #expect(model.path == [.series(Self.series("freek"))])
    }

    @Test("FR-HOME-04: a pinned series' tile is the episode it continues with, and plays it")
    func pinnedTileIsTheNextEpisode() async throws {
        await pins.pin(Self.series("freek"), in: .normal)
        let entry = Self.live("freek")
        await history.record(entry, in: .normal)
        let model = model()
        await model.refresh()
        let tile = try #require(model.pinned.first)

        model.select(tile)

        #expect(tile.state == .continues(try #require(entry.next), fraction: nil))
        #expect(model.playing?.playable.id == entry.next?.id)
    }

    @Test("FR-HOME-04, FR-HOME-07: a pinned series watched to its end says so, also after it has left the row")
    func finishedPinStaysPinned() async throws {
        await pins.pin(Self.series("freek"), in: .normal)
        await history.record(Self.finished("freek", ago: 30 * Self.day), in: .normal)
        let model = model()

        await model.refresh()

        #expect(model.continuing.isEmpty)
        #expect(try #require(model.pinned.first).state == .finished)
    }

    @Test("FR-HOME-08: removing takes the tile away at once, and leaves the position and the page's next episode")
    func removingHidesTheTile() async throws {
        let entry = Self.live("freek")
        await history.record(entry, in: .normal)
        let next = try #require(entry.next)
        await stopped(next.id, of: nil)
        let model = model()
        await model.refresh()

        await model.remove(entry.id)

        #expect(model.continuing.isEmpty)
        #expect(model.path.isEmpty)
        #expect(await progress.progress(of: next.id, in: .normal)?.offset == 150)
        #expect(await history.entry(for: entry.id, in: .normal)?.next == next)
    }

    @Test("FR-HOME-11: an item pushed off the row keeps its position, and comes back to the front when played")
    func evictedItemKeepsItsPlace() async throws {
        let evicted = Self.live("oldest", played: 1000)
        let next = try #require(evicted.next)
        await history.record(evicted, in: .normal)
        await stopped(next.id, of: 600)
        for number in 1...20 {
            await history.record(Self.live("series-\(number)", played: TimeInterval(number)), in: .normal)
        }
        let model = model()
        await model.refresh()
        #expect(!model.continuing.contains { $0.id == evicted.id })
        #expect(await progress.progress(of: next.id, in: .normal)?.offset == 150)
        #expect(await history.entry(for: evicted.id, in: .normal)?.next == next)

        // Played again, from its page or from search.
        await history.record(Self.live("oldest"), in: .normal)
        await model.refresh()

        #expect(model.continuing.first?.id == evicted.id)
        #expect(model.continuing.first?.state == .continues(next, fraction: 0.25))
    }

    @Test("FR-HOME-08: removing a series from the row does not unpin it")
    func removingDoesNotUnpin() async {
        await pins.pin(Self.series("freek"), in: .normal)
        await history.record(Self.live("freek"), in: .normal)
        let model = model()
        await model.refresh()

        await model.remove(Self.series("freek").id)

        #expect(model.continuing.isEmpty)
        #expect(model.pinned.count == 1)
    }

    @Test("FR-HOME-05: unpinning does not take the series off the row")
    func unpinningLeavesTheRow() async {
        await pins.pin(Self.series("freek"), in: .normal)
        await history.record(Self.live("freek"), in: .normal)
        let model = model()
        await model.refresh()

        await model.unpin(Self.series("freek").id)

        #expect(model.pinned.isEmpty)
        #expect(model.continuing.count == 1)
    }

    @Test("FR-HOME-06, FR-MODE-05: each mode has a row of its own")
    func rowsArePerMode() async {
        await history.record(Self.live("freek"), in: .kids)
        let normal = model()
        let kids = model(in: .kids)

        await normal.refresh()
        await kids.refresh()

        #expect(normal.continuing.isEmpty)
        #expect(kids.continuing.count == 1)
    }

    @Test("FR-HOME-10: when the player closes the rows show what was just watched")
    func playbackEndingRefreshes() async {
        let model = model()
        await model.refresh()
        await history.record(Self.live("freek"), in: .normal)

        await model.playbackEnded()

        #expect(model.continuing.map(\.title) == ["freek"])
        #expect(model.playbacksEnded == 1)
    }

    @Test("FR-HOME-07: a single programme that was finished shows as finished, and plays again when selected")
    func singleProgrammeOnTheRow() async throws {
        let film = Self.episode("film")
        await history.record(WatchedEntry(single: film, playedAt: Self.now), in: .normal)
        let model = model()
        await model.refresh()
        let tile = try #require(model.continuing.first)

        model.select(tile)

        #expect(tile.kind == .single)
        #expect(model.playing == PlayRequest(playable: Upcoming(film, in: nil).playable, origin: .single))
    }
}
