//
//  ModeUITests.swift
//  NPO lightUITests
//

import XCTest

final class ModeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // Requirement: FR-MODE-02, FR-MODE-03
    @MainActor
    func testModeIsSwitchedInOneAction() throws {
        let app = XCUIApplication()
        let remote = XCUIRemote.shared
        app.launchEnvironment["NPO_LIGHT_SCENARIO"] = "signed-in"
        app.launch()

        let badge = app.descendants(matching: .any)["kids-mode-badge"]
        let toKids = app.buttons["mode-to-kids"]
        XCTAssertTrue(toKids.waitForExistence(timeout: 10))
        XCTAssertFalse(badge.exists)

        // The switch is beside search, on the home page itself.
        for direction in [XCUIRemote.Button.up, .up, .right, .right] where !toKids.hasFocus {
            remote.press(direction)
        }
        XCTAssertTrue(toKids.hasFocus)
        remote.press(.select)

        // Kids mode says that it is kids mode, and offers the way back.
        XCTAssertTrue(badge.waitForExistence(timeout: 10))
        let toNormal = app.buttons["mode-to-normal"]
        XCTAssertTrue(toNormal.exists)
        XCTAssertTrue(app.buttons["home-search"].exists)

        for direction in [XCUIRemote.Button.up, .up, .right, .right] where !toNormal.hasFocus {
            remote.press(direction)
        }
        XCTAssertTrue(toNormal.hasFocus)
        remote.press(.select)

        XCTAssertTrue(toKids.waitForExistence(timeout: 10))
        XCTAssertFalse(badge.exists)
    }
}
