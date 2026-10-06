//
//  ModeModelTests.swift
//  NPO lightTests
//

import Foundation
import Synchronization
import Testing
@testable import NPO_light

@MainActor
struct ModeModelTests {
    /// A catalogue that answers with these modes, or cannot be reached.
    nonisolated private final class Modes: Catalogue {
        private let modes: Mutex<Set<Mode>?>

        init(_ answer: Set<Mode>?) {
            modes = Mutex(answer)
        }

        func answer(_ answer: Set<Mode>?) {
            modes.withLock { $0 = answer }
        }

        func availableModes() async throws -> Set<Mode> {
            guard let answer = modes.withLock({ $0 }) else { throw BackendError.unreachable }
            return answer
        }

        func search(for query: String, in mode: Mode) async throws -> SearchResults { .empty }
        func series(_ id: ItemID, in mode: Mode) async throws -> SeriesDetail { StubCatalogue.detail }
        func episodes(of season: SeasonID, in mode: Mode) async throws -> [Playable] { [] }
        func place(of episode: EpisodeID, in mode: Mode) async throws -> SeriesPlace? { nil }
        func programme(_ id: EpisodeID, in mode: Mode) async throws -> ProgrammeDetail { StubCatalogue.film(id) }
        func continuing(in mode: Mode) async throws -> [Continued] { [] }
        func discontinue(_ episode: EpisodeID, in mode: Mode) async throws {}
    }

    private func withSuite(_ body: (String) async throws -> Void) async rethrows {
        let suite = "mode-tests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        try await body(suite)
    }

    private func model(_ initial: Mode = .normal, modes: Set<Mode>?) -> ModeModel {
        ModeModel(initial: initial, catalogue: Modes(modes), keep: { _ in })
    }

    @Test("FR-MODE-01: a fresh install starts in normal mode")
    func freshInstallIsNormal() async {
        await withSuite { suite in
            #expect(StoredMode(suite: suite).mode == .normal)
        }
    }

    @Test("FR-MODE-01: the mode the app was switched to is the one the next launch starts in")
    func modeIsRemembered() async {
        await withSuite { suite in
            let stored = StoredMode(suite: suite)
            let model = ModeModel(initial: stored.mode, catalogue: Modes([.normal, .kids])) { stored.mode = $0 }
            await model.load()

            model.switchMode()

            #expect(model.current == .kids)
            #expect(StoredMode(suite: suite).mode == .kids)
        }
    }

    @Test("FR-MODE-02: switching is one action in either direction, with nothing asked")
    func switchingGoesBothWays() async {
        let model = model(modes: [.normal, .kids])
        await model.load()
        #expect(model.canSwitch)

        model.switchMode()
        #expect(model.current == .kids)

        model.switchMode()
        #expect(model.current == .normal)
    }

    @Test("FR-MODE-02: an account without a kids profile has no switch, and is told why")
    func noKidsProfileNoSwitch() async {
        let model = model(modes: [.normal])

        await model.load()
        model.switchMode()

        #expect(!model.canSwitch)
        #expect(model.explainsMissingProfile)
        #expect(model.current == .normal)
    }

    @Test("FR-MODE-02: before NPO has said whether there is a kids profile, nothing is offered and nothing explained")
    func unknownOffersNothing() async {
        let model = model(modes: nil)

        await model.load()

        #expect(model.kidsProfile == .unknown)
        #expect(!model.canSwitch)
        #expect(!model.explainsMissingProfile)
    }

    @Test("FR-MODE-02: a kids profile made after signing in is found the next time the home page asks")
    func laterKidsProfileIsFound() async {
        let catalogue = Modes([.normal])
        let model = ModeModel(initial: .normal, catalogue: catalogue, keep: { _ in })
        await model.load()
        #expect(!model.canSwitch)

        catalogue.answer([.normal, .kids])
        await model.load()

        #expect(model.canSwitch)
        #expect(!model.explainsMissingProfile)
    }

    @Test("FR-MODE-04: a stored kids mode on an account without a kids profile falls back to normal mode")
    func storedKidsModeFallsBack() async {
        var kept: [Mode] = []
        let model = ModeModel(initial: .kids, catalogue: Modes([.normal])) { kept.append($0) }

        await model.load()

        #expect(model.current == .normal)
        #expect(kept == [.normal])
    }

    @Test("FR-MODE-02: kids mode can always be left, also while NPO cannot be asked")
    func kidsModeCanAlwaysBeLeft() async {
        let model = model(.kids, modes: nil)
        await model.load()
        #expect(model.current == .kids)

        model.switchMode()

        #expect(model.current == .normal)
    }
}
