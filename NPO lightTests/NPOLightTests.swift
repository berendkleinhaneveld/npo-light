//
//  NPOLightTests.swift
//  NPO lightTests
//
//  Created by Berend Klein Haneveld on 29/08/2026.
//

import Foundation
import Testing
@testable import NPO_light

struct NPOLightTests {
    @Test func itemKeepsItsTimestamp() async throws {
        let timestamp = Date(timeIntervalSince1970: 0)

        let item = Item(timestamp: timestamp)

        #expect(item.timestamp == timestamp)
    }
}
