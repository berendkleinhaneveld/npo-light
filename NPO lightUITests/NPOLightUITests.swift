//
//  NPOLightUITests.swift
//  NPO lightUITests
//
//  Created by Berend Klein Haneveld on 29/08/2026.
//

import XCTest

final class NPOLightUITests: XCTestCase {
    override func setUpWithError() throws {
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
    }

    @MainActor
    func testApplicationLaunches() throws {
        let app = XCUIApplication()

        app.launch()

        XCTAssertEqual(app.state, .runningForeground)
    }
}
