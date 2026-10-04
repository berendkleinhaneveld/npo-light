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

    // Requirement: FR-SEARCH-01
    @MainActor
    func testSearchIsOneActionFromHome() throws {
        let app = XCUIApplication()
        app.launchEnvironment["NPO_LIGHT_SCENARIO"] = "signed-in"

        app.launch()

        XCTAssertTrue(app.buttons["home-search"].waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.select)

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))

        // Requirement: FR-SEARCH-02
        field.typeText("fr")

        XCTAssertTrue(app.buttons["Freeks wilde wereld, serie"].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Search results"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
