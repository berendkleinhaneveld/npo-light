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

    // Requirement: FR-AUTH-01, FR-AUTH-06
    @MainActor
    func testLaunchWithoutSessionShowsSignIn() throws {
        let app = XCUIApplication()
        // The app's own double, named by the launch environment: a UI test
        // cannot inject one, and must not start a real sign-in at NPO.
        app.launchEnvironment["NPO_LIGHT_SCENARIO"] = "awaiting-approval"

        app.launch()

        let code = app.staticTexts["sign-in-code"]
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        XCTAssertEqual(code.label, "51411921")
        XCTAssertTrue(app.descendants(matching: .any)["sign-in-qr-code"].exists)
        XCTAssertEqual(app.textFields.count + app.secureTextFields.count, 0)
    }
}
