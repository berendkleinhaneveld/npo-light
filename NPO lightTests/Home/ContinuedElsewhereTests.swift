//
//  ContinuedElsewhereTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// What NPO lists to go on with, taken onto the television's own row.
@MainActor
struct ContinuedElsewhereTests {
    nonisolated private static let now = Date(timeIntervalSince1970: 10_000_000)
    nonisolated private static let hour: TimeInterval = 3600
    nonisolated private static let season = SeasonID(rawValue: "season-1")
    nonisolated private static let series = SeriesSummary(id: ItemID(rawValue: "series-1"),
                                                          title: "Wisting",
                                                          artwork: nil)

    private let progress = ScriptedProgress()
    private let history = ScriptedWatchHistory()
    private let later = ScriptedWatchLater()
    private let clock = TestClock(now: ContinuedElsewhereTests.now)

    /// NPO places every episode in the one series, unless told otherwise.
    private let catalogue = StubCatalogue(
        season: { _ in [ContinuedElsewhereTests.episode("one"), ContinuedElsewhereTests.episode("two")] },
        place: { _ in SeriesPlace(series: ContinuedElsewhereTests.series, season: ContinuedElsewhereTests.season) }
    )

    private var watched: WatchedState {
        WatchedState(progress: progress, history: history, later: later)
    }

    private func elsewhere(over catalogue: StubCatalogue? = nil) -> ContinuedElsewhere {
        let catalogue = catalogue ?? self.catalogue
        return ContinuedElsewhere(catalogue: catalogue,
                                  watched: watched,
                                  coordinator: PlaybackCoordinator(watched: watched,
                                                                   order: EpisodeOrder(catalogue: catalogue),
                                                                   clock: clock),
                                  clock: clock)
    }

    nonisolated private static func episode(_ name: String, at offset: TimeInterval? = nil) -> Playable {
        Playable(id: EpisodeID(rawValue: name), title: "Wisting", caption: "45m • \(name)", synopsis: nil,
                 duration: nil, artwork: nil, position: offset.map { SharedPosition(offset: $0, duration: hour) })
    }

    nonisolated private static func listed(_ name: String, at offset: TimeInterval, single: Bool = false) -> Continued {
        Continued(playable: episode(name, at: offset), isSingle: single)
    }

    @Test("FR-HOME-12: an episode started on another device is on the row, in its series, this far in")
    func episodeStartedElsewhereIsOnTheRow() async {
        catalogue.list(.success([Self.listed("one", at: 900)]))

        let changed = await elsewhere().take(in: .normal)

        #expect(changed)
        let entry = await history.entry(for: Self.series.id, in: .normal)
        #expect(entry?.kind == .series)
        #expect(entry?.next?.id == EpisodeID(rawValue: "one"))
        #expect(entry?.next?.season == Self.season)
        #expect(await progress.progress(of: EpisodeID(rawValue: "one"), in: .normal)?.offset == 900)
    }

    @Test("FR-HOME-12: a programme with a page of its own is on the row as itself, without asking where it belongs")
    func singleProgrammeIsItsOwnEntry() async {
        let unplaced = StubCatalogue(place: { _ in throw BackendError.unreachable })
        unplaced.list(.success([Self.listed("film", at: 1200, single: true)]))

        #expect(await elsewhere(over: unplaced).take(in: .normal))

        #expect(await history.entry(for: ItemID(rawValue: "film"), in: .normal)?.kind == .single)
    }

    @Test("FR-HOME-12: what NPO lists first is first on the row")
    func npoOrderIsTheRowsOrder() async {
        let apart = StubCatalogue(place: { _ in nil })
        apart.list(.success(["latest", "earlier", "first"].map { Self.listed($0, at: 60) }))

        _ = await elsewhere(over: apart).take(in: .normal)

        let row = ContinueWatching.row(from: await history.entries(in: .normal), at: Self.now)
        #expect(row.map(\.id.rawValue) == ["latest", "earlier", "first"])
    }

    @Test("FR-HOME-12, FR-HOME-08: what the row already continues with keeps its place, and stays off it when hidden")
    func knownThreadKeepsItsPlace() async throws {
        let before = WatchedEntry(series: Self.series,
                                  next: Upcoming(Self.episode("one"), in: Self.season),
                                  playedAt: Self.now.addingTimeInterval(-86_400))
        await history.record(before, in: .normal)
        await history.hide(Self.series.id, in: .normal)
        catalogue.list(.success([Self.listed("one", at: 900)]))

        let changed = await elsewhere().take(in: .normal)

        // The tile's progress is news; the entry is as it was.
        #expect(changed)
        let entry = try #require(await history.entry(for: Self.series.id, in: .normal))
        #expect(entry.isHidden)
        #expect(entry.playedAt == before.playedAt)
        #expect(await progress.progress(of: EpisodeID(rawValue: "one"), in: .normal)?.offset == 900)
    }

    @Test("FR-HOME-12: NPO repeating what it listed before does not bring back what the row moved on from")
    func repeatedListChangesNothing() async {
        catalogue.list(.success([Self.listed("one", at: 900)]))
        let elsewhere = elsewhere()
        _ = await elsewhere.take(in: .normal)
        // Played on here, to the next episode.
        let moved = WatchedEntry(series: Self.series,
                                 next: Upcoming(Self.episode("two"), in: Self.season),
                                 playedAt: Self.now)
        await history.record(moved, in: .normal)
        clock.advance(by: .seconds(ContinuedElsewhere.pace))

        let changed = await elsewhere.take(in: .normal)

        #expect(!changed)
        #expect(await history.entry(for: Self.series.id, in: .normal)?.next?.id == EpisodeID(rawValue: "two"))
    }

    @Test("FR-HOME-12: a series the row has continues with the episode it was moved to on another device")
    func seriesMovesToTheEpisodeNPONames() async {
        await history.record(WatchedEntry(series: Self.series,
                                          next: Upcoming(Self.episode("one"), in: Self.season),
                                          playedAt: Self.now.addingTimeInterval(-86_400)),
                             in: .normal)
        catalogue.list(.success([Self.listed("two", at: 300)]))

        #expect(await elsewhere().take(in: .normal))

        let entries = await history.entries(in: .normal)
        #expect(entries.count == 1)
        #expect(entries.first?.next?.id == EpisodeID(rawValue: "two"))
    }

    @Test("FR-HOME-12: something NPO lists as watched to its end starts nothing, and is marked watched")
    func finishedElsewhereStartsNothing() async {
        catalogue.list(.success([Self.listed("one", at: 3590)]))

        #expect(await !elsewhere().take(in: .normal))

        #expect(await history.entries(in: .normal).isEmpty)
        #expect(await progress.progress(of: EpisodeID(rawValue: "one"), in: .normal)?.isFinished == true)
    }

    @Test("FR-HOME-12, FR-HOME-07: an episode finished on another device leaves its series on the next one")
    func finishedElsewhereMovesTheSeriesOn() async {
        await history.record(WatchedEntry(series: Self.series,
                                          next: Upcoming(Self.episode("one"), in: Self.season),
                                          playedAt: Self.now),
                             in: .normal)
        await later.save(SavedItem(Self.episode("one"), origin: .unknown), in: .normal)
        catalogue.list(.success([Self.listed("one", at: 3590)]))

        #expect(await elsewhere().take(in: .normal))

        #expect(await history.entry(for: Self.series.id, in: .normal)?.next?.id == EpisodeID(rawValue: "two"))
        // Watched to its end is watched, wherever: it leaves the watch later
        // list too (FR-LATER-07).
        #expect(await later.saved(in: .normal).isEmpty)
    }

    @Test("FR-HOME-12: an episode NPO could not place now is taken in the next time it can")
    func unplacedEpisodeIsTriedAgain() async {
        let reachable = Counter()
        let flaky = StubCatalogue(place: { _ in
            guard reachable.increment() > 1 else { throw BackendError.unreachable }
            return SeriesPlace(series: ContinuedElsewhereTests.series, season: ContinuedElsewhereTests.season)
        })
        flaky.list(.success([Self.listed("one", at: 900)]))
        let elsewhere = elsewhere(over: flaky)

        #expect(await !elsewhere.take(in: .normal))
        #expect(await history.entries(in: .normal).isEmpty)
        clock.advance(by: .seconds(ContinuedElsewhere.pace))

        #expect(await elsewhere.take(in: .normal))
        #expect(await history.entry(for: Self.series.id, in: .normal) != nil)
    }

    @Test("FR-HOME-12, FR-MODE-05: what a profile goes on with is taken into its own mode only")
    func takenIntoItsOwnMode() async {
        catalogue.list(.success([Self.listed("one", at: 900)]))

        _ = await elsewhere().take(in: .kids)

        #expect(await history.entries(in: .normal).isEmpty)
        #expect(await history.entries(in: .kids).count == 1)
    }

    @Test("FR-HOME-12: NPO is not asked again within a minute of answering, however often the home page returns")
    func npoIsAskedAtAPace() async {
        let asked = Counter()
        let counting = StubCatalogue(place: { _ in
            asked.increment()
            return nil
        })
        let elsewhere = elsewhere(over: counting)
        counting.list(.success([Self.listed("one", at: 900)]))
        _ = await elsewhere.take(in: .normal)
        counting.list(.success([Self.listed("two", at: 900)]))

        #expect(await !elsewhere.take(in: .normal))
        #expect(asked.value == 1)

        clock.advance(by: .seconds(ContinuedElsewhere.pace))
        #expect(await elsewhere.take(in: .normal))
        #expect(asked.value == 2)
    }

    // MARK: taking off

    @Test("FR-SET-05: erasing a mode takes everything NPO lists for its profile off NPO's row")
    func erasingClearsNPOsRow() async {
        catalogue.list(.success([Self.listed("one", at: 900), Self.listed("film", at: 60, single: true)]))
        let elsewhere = elsewhere()
        _ = await elsewhere.take(in: .normal)
        let eraser = ErasingElsewhere(wrapping: ScriptedEraser(history: history, later: later, progress: progress),
                                      elsewhere: elsewhere)

        await eraser.erase([.normal])

        #expect(catalogue.discontinued == [EpisodeID(rawValue: "one"), EpisodeID(rawValue: "film")])
        #expect(await history.entries(in: .normal).isEmpty)
    }

    @Test("FR-SET-05, FR-SET-04: what NPO still lists just after an erase does not fill the row again")
    func erasedRowStaysEmpty() async {
        // NPO answers a removal at once and acts on it seconds later.
        catalogue.list(.success([Self.listed("one", at: 900)]))
        let elsewhere = elsewhere()
        let model = home(over: catalogue, elsewhere: elsewhere)
        await ErasingElsewhere(wrapping: ScriptedEraser(history: history, later: later, progress: progress),
                               elsewhere: elsewhere).erase([.normal])

        await model.refresh()
        await model.catchUp()

        #expect(model.continuing.isEmpty)
    }

    @Test("FR-SET-05: a television is erased whether or not NPO answers")
    func erasesWithoutNPO() async {
        await history.record(WatchedEntry(single: Self.episode("here"), playedAt: Self.now), in: .normal)
        catalogue.list(.failure(.unreachable))

        await ErasingElsewhere(wrapping: ScriptedEraser(history: history, later: later, progress: progress),
                               elsewhere: elsewhere()).erase([.normal])

        #expect(await history.entries(in: .normal).isEmpty)
        #expect(catalogue.discontinued.isEmpty)
    }

    @Test("FR-HOME-13: taking an item off the row takes what it continues with off NPO's row too")
    func removingTellsNPO() async {
        catalogue.list(.success([Self.listed("one", at: 900)]))
        let model = home(over: catalogue)
        await model.refresh()
        await model.catchUp()

        await model.remove(Self.series.id)

        #expect(model.continuing.isEmpty)
        #expect(catalogue.discontinued == [EpisodeID(rawValue: "one")])
        // NPO keeps where it was watched to, and so does the television
        // (FR-HOME-08).
        #expect(await progress.progress(of: EpisodeID(rawValue: "one"), in: .normal)?.offset == 900)
    }

    @Test("FR-HOME-13: what was taken off stays off while NPO still lists it")
    func removedStaysOffTheRow() async {
        catalogue.list(.success([Self.listed("one", at: 900)]))
        let model = home(over: catalogue)
        await model.catchUp()
        await model.remove(Self.series.id)
        clock.advance(by: .seconds(ContinuedElsewhere.pace))

        await model.catchUp()

        #expect(model.continuing.isEmpty)
    }

    @Test("FR-HOME-13, FR-HOME-08: the tile goes when NPO cannot be told")
    func removingWorksWithoutNPO() async {
        await history.record(WatchedEntry(single: Self.episode("here"), playedAt: Self.now), in: .normal)
        catalogue.list(.failure(.unreachable))
        let model = home(over: catalogue)
        await model.refresh()

        await model.remove(ItemID(rawValue: "here"))

        #expect(model.continuing.isEmpty)
    }

    // MARK: the home page

    private func home(over catalogue: StubCatalogue, elsewhere: ContinuedElsewhere? = nil) -> HomeModel {
        HomeModel(pins: ScriptedPins(),
                  watched: watched,
                  catalogue: catalogue,
                  clock: clock,
                  mode: .normal,
                  elsewhere: elsewhere ?? self.elsewhere(over: catalogue))
    }

    @Test("FR-HOME-12, NFR-PERF-03: the home page shows what the television knows, then what NPO adds to it")
    func homeCatchesUpBehindItsRows() async {
        await history.record(WatchedEntry(single: Self.episode("here"), playedAt: Self.now.addingTimeInterval(-60)),
                             in: .normal)
        catalogue.list(.success([Self.listed("one", at: 900)]))
        let model = home(over: catalogue)

        await model.refresh()
        #expect(model.continuing.map(\.id.rawValue) == ["here"])

        await model.catchUp()

        #expect(model.continuing.map(\.id) == [Self.series.id, ItemID(rawValue: "here")])
        #expect(model.continuing.first?.state == .continues(Upcoming(Self.episode("one"), in: Self.season),
                                                            fraction: 0.25))
    }

    @Test("FR-HOME-12: NPO not answering leaves the row as it is")
    func unreachableNPOLeavesTheRow() async {
        await history.record(WatchedEntry(single: Self.episode("here"), playedAt: Self.now), in: .normal)
        catalogue.list(.failure(.unreachable))
        let model = home(over: catalogue)
        await model.refresh()

        await model.catchUp()

        #expect(model.continuing.map(\.id.rawValue) == ["here"])
    }
}
