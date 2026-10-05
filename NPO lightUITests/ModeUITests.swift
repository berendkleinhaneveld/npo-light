//
//  ModeUITests.swift
//  NPO lightUITests
//

import XCTest

final class ModeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // Requirement: FR-MODE-02, FR-MODE-03, FR-MODE-06, FR-SET-01
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
        XCTAssertTrue(app.buttons["home-settings"].exists)

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
        // Kids mode has no way into settings.
        XCTAssertFalse(app.buttons["home-settings"].exists)

        for direction in [XCUIRemote.Button.up, .up, .right, .right] where !toNormal.hasFocus {
            remote.press(direction)
        }
        XCTAssertTrue(toNormal.hasFocus)
        remote.press(.select)

        XCTAssertTrue(toKids.waitForExistence(timeout: 10))
        XCTAssertFalse(badge.exists)
    }

    // Requirement: NFR-REL-05
    @MainActor
    func testResetIsToldOnce() throws {
        let app = XCUIApplication()
        let remote = XCUIRemote.shared
        app.launchEnvironment["NPO_LIGHT_SCENARIO"] = "signed-in"
        app.launchEnvironment["NPO_LIGHT_STORE_RESET"] = "1"
        app.launch()

        // The app works, and says what happened.
        let acknowledge = app.buttons["reset-notice-ok"]
        XCTAssertTrue(acknowledge.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["home-search"].exists)

        for direction in [XCUIRemote.Button.up, .up, .up, .down] where !acknowledge.hasFocus {
            remote.press(direction)
        }
        XCTAssertTrue(acknowledge.hasFocus)
        remote.press(.select)

        XCTAssertFalse(acknowledge.exists)
        XCTAssertTrue(app.buttons["home-search"].exists)
    }
}
