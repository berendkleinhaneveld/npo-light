//
//  LaunchNoticeTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

@MainActor
struct LaunchNoticeTests {
    @Test("NFR-REL-05: a store that was started over is told to the user until it is acknowledged, and then no more")
    func resetIsToldOnce() {
        let notice = LaunchNotice(positionsWereReset: true)
        #expect(notice.positionsWereReset)

        notice.acknowledge()

        #expect(!notice.positionsWereReset)
    }

    @Test("NFR-REL-05: a store tvOS emptied is filled from its copy, and that is not a reset to tell anyone about")
    func evictionIsNotAReset() async throws {
        let name = "notice-tests-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appending(path: name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults.standard.removePersistentDomain(forName: name)
        }

        // Nothing there: a first launch, or a launch after an eviction.
        #expect(!ProgressStore.open(in: directory, suite: name).wasReset)

        // Something there that is not a store.
        try Data("not a store".utf8).write(to: directory.appending(path: "positions.store"))
        let reset = ProgressStore.open(in: directory, suite: name)

        #expect(reset.wasReset)
        #expect(await reset.progress(of: EpisodeID(rawValue: "any"), in: .normal) == nil)
    }
}
