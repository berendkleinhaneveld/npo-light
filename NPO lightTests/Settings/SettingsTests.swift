//
//  SettingsTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

@MainActor
struct SettingsTests {
    private func withSuite(_ body: (String) async throws -> Void) async rethrows {
        let suite = "settings-tests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        try await body(suite)
    }

    @Test("FR-SET-02: a fresh install uses five seconds, one hour and three hours")
    func defaults() async {
        await withSuite { suite in
            let timings = StoredTimings(suite: suite).timings

            #expect(timings[.kidsPause] == 5)
            #expect(timings[.kidsStillWatching] == 3600)
            #expect(timings[.normalStillWatching] == 10800)
            #expect(timings.stillWatching(in: .kids) == .seconds(3600))
            #expect(timings.stillWatching(in: .normal) == .seconds(10800))
        }
    }

    @Test("FR-SET-02: each setting offers a few choices, and its default is one of them",
          arguments: Timings.Setting.allCases)
    func choicesIncludeTheDefault(setting: Timings.Setting) {
        #expect(setting.choices.contains(setting.standard))
        #expect((3...6).contains(setting.choices.count))
    }

    @Test("FR-SET-02: a chosen value is used at once and is there after a relaunch")
    func chosenValuePersists() async {
        await withSuite { suite in
            let stored = StoredTimings(suite: suite)
            let model = SettingsModel(timings: stored.timings, eraser: ScriptedEraser(),
                                      keep: { stored.keep($0, for: $1) }, signOut: {})

            model.choose(15, for: .kidsPause)

            #expect(model.timings[.kidsPause] == 15)
            #expect(StoredTimings(suite: suite).timings[.kidsPause] == 15)
            // The other two are independent of it.
            #expect(StoredTimings(suite: suite).timings[.kidsStillWatching] == 3600)
        }
    }

    @Test("FR-SET-02: a stored value that cannot be read, or is none of the choices, is the default")
    func unreadableValueFallsBack() async {
        await withSuite { suite in
            let defaults = UserDefaults(suiteName: suite)
            defaults?.set("soon", forKey: "settings.kidsPause")
            defaults?.set(7, forKey: "settings.kidsStillWatching")

            let timings = StoredTimings(suite: suite).timings

            #expect(timings[.kidsPause] == 5)
            #expect(timings[.kidsStillWatching] == 3600)
        }
    }

    @Test("FR-SET-02: something that is not one of the choices cannot be chosen")
    func onlyChoicesCanBeChosen() {
        var kept: [Int] = []
        let model = SettingsModel(timings: Timings(), eraser: ScriptedEraser(),
                                  keep: { value, _ in kept.append(value) }, signOut: {})

        model.choose(7, for: .kidsPause)

        #expect(model.timings[.kidsPause] == 5)
        #expect(kept.isEmpty)
    }

    @Test("FR-SET-03, FR-AUTH-04: signing out forgets the session, and leaves what is kept here")
    func signOutLeavesLocalData() async {
        let eraser = ScriptedEraser()
        await eraser.pins.pin(StubCatalogue.results.series[0], in: .normal)
        let app = AppModel(authenticator: ScriptedAuthenticator(.signedIn))
        await app.restore()
        let model = SettingsModel(timings: Timings(), eraser: eraser, keep: { _, _ in }, signOut: { app.signOut() })

        model.signOut()

        #expect(app.session == .signedOut)
        #expect(await eraser.pins.pinned(in: .normal).count == 1)
    }

    @Test("FR-SET-04: erasing does not sign out, and says that it was done")
    func erasingKeepsTheSession() async {
        var signedOut = false
        let model = SettingsModel(timings: Timings(),
                                  eraser: ScriptedEraser(),
                                  keep: { _, _ in },
                                  signOut: { signedOut = true })
        #expect(model.erased == nil)

        await model.erase([.kids])

        #expect(model.erased == [.kids])
        #expect(!signedOut)
    }

    @Test("FR-MODE-06, FR-SET-01: settings open from the normal-mode home page, and from no kids-mode one")
    func settingsAreNormalModeOnly() {
        let normal = HomeModel(pins: ScriptedPins(), mode: .normal)
        let kids = HomeModel(pins: ScriptedPins(), mode: .kids)

        normal.openSettings()
        kids.openSettings()

        #expect(normal.path == [.settings])
        #expect(kids.path.isEmpty)
    }
}
