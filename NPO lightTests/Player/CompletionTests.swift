//
//  CompletionTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

struct CompletionTests {
    @Test("FR-PLAY-04: a 60-minute episode is finished at 58:30, and a 10-minute episode at 9:30", arguments: [
        (3600.0, 3510.0),
        (600.0, 570.0)
    ])
    func finishPointIsTheLaterOfTheTwo(duration: TimeInterval, point: TimeInterval) {
        #expect(Completion.finishPoint(of: duration) == point)
        #expect(Completion.isFinished(at: point, of: duration))
        #expect(!Completion.isFinished(at: point - 1, of: duration))
    }

    @Test("FR-PLAY-04: an episode shorter than 90 seconds is finished at 95% of it, never at a negative position")
    func shortEpisodeUsesTheFraction() throws {
        let point = try #require(Completion.finishPoint(of: 60))

        #expect(point == 57)
        #expect(!Completion.isFinished(at: 0, of: 60))
    }

    @Test("FR-PLAY-04: an episode of unknown duration is not finished by any position", arguments: [
        nil, 0.0, TimeInterval.nan, TimeInterval.infinity
    ] as [TimeInterval?])
    func unknownDurationIsNeverFinished(duration: TimeInterval?) {
        #expect(Completion.finishPoint(of: duration) == nil)
        #expect(!Completion.isFinished(at: 100_000, of: duration))
    }
}
