//
//  SettingsUITests.swift
//  NPO lightUITests
//

import XCTest

final class SettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // Requirement: FR-SET-02
    @MainActor
    func testTimingIsChosenFromItsList() throws {
        let app = XCUIApplication()
        let remote = XCUIRemote.shared
        app.launchEnvironment["NPO_LIGHT_SCENARIO"] = "signed-in"
        app.launch()

        let settings = app.buttons["home-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        // Settings is the last thing in the header, after search and the
        // mode switch.
        for direction in [XCUIRemote.Button.up, .up, .right, .right, .right] where !settings.hasFocus {
            remote.press(direction)
        }
        XCTAssertTrue(settings.hasFocus)
        remote.press(.select)

        // The row shows the value in use; selecting it opens the choices.
        let row = app.descendants(matching: .any)["setting-kidsStillWatching"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        for _ in 0..<3 where !row.hasFocus {
            remote.press(.down)
        }
        XCTAssertTrue(row.hasFocus)
        remote.press(.select)

        let shortest = app.buttons["10 min"]
        XCTAssertTrue(shortest.waitForExistence(timeout: 10))
        for _ in 0..<6 where !shortest.hasFocus {
            remote.press(.up)
        }
        XCTAssertTrue(shortest.hasFocus)
        remote.press(.select)

        // Back on settings, the row says what was chosen.
        XCTAssertTrue(shortest.waitForNonExistence(timeout: 10))
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let saysIt = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "10 min", "10 min")
        XCTAssertTrue(app.descendants(matching: .any).matching(saysIt).firstMatch.waitForExistence(timeout: 10))
    }
}
