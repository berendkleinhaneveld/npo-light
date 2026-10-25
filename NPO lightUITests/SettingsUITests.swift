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
        // Focus lands on the row's cell, around the picker that says the
        // value.
        let picker = app.buttons["setting-kidsStillWatching"].firstMatch
        let row = app.cells.containing(.button, identifier: "setting-kidsStillWatching").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        for _ in 0..<3 where !row.hasFocus {
            remote.press(.down)
        }
        XCTAssertTrue(row.hasFocus)
        remote.press(.select)

        let shortest = app.cells["10 min"].firstMatch
        XCTAssertTrue(shortest.waitForExistence(timeout: 10))
        for _ in 0..<6 where !shortest.hasFocus {
            remote.press(.up)
        }
        XCTAssertTrue(shortest.hasFocus)
        remote.press(.select)

        // Back on settings, the row says what was chosen.
        XCTAssertTrue(shortest.waitForNonExistence(timeout: 10))
        let chosen = expectation(for: NSPredicate(format: "value == %@", "10 min"), evaluatedWith: picker)
        wait(for: [chosen], timeout: 10)
    }
}
