//
//  HomeFocusUITests.swift
//  NPO lightUITests
//

import XCTest

final class HomeFocusUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // Requirement: FR-HOME-08, FR-HOME-10, FR-LATER-05, FR-LATER-09
    @MainActor
    func testFocusSurvivesATileLeaving() throws {
        let app = XCUIApplication()
        let remote = XCUIRemote.shared
        app.launchEnvironment["NPO_LIGHT_SCENARIO"] = "signed-in"
        app.launchEnvironment["NPO_LIGHT_HOME"] = "filled"
        app.launch()

        let first = app.buttons["continue-series-1"]
        let second = app.buttons["continue-series-2"]
        let saved = app.buttons["later-playable-2"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(saved.exists)

        // Onto the first tile of the row, wherever the page opened: on the
        // way to search above the rows, or on a tile already. Down until
        // focus is in the row, then left to its start.
        let row = [first, second, app.buttons["continue-playable-2"]]
        for _ in 0..<3 where !row.contains(where: \.hasFocus) {
            remote.press(.down)
        }
        XCTAssertTrue(row.contains(where: \.hasFocus), "Focus never reached the row")
        for _ in 0..<2 where !first.hasFocus {
            remote.press(.left)
        }
        XCTAssertTrue(first.hasFocus, "Focus never reached the first tile")

        // Taken off the row from its menu, whose last entry removes it: the
        // tile after it has focus, not nothing.
        remove(times: 3, with: remote)
        waitForFocus(on: second)
        XCTAssertFalse(first.exists)

        // The last saved item takes its row with it, heading and all, and
        // focus is still somewhere.
        remote.press(.down)
        waitForFocus(on: saved)
        remove(times: 2, with: remote)
        let holders = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true"))
        XCTAssertTrue(holders.firstMatch.waitForExistence(timeout: 10), "Nothing has focus")
        XCTAssertFalse(saved.exists)
    }

    /// Holds select for the menu, and chooses the entry `times` down, which
    /// is the removal: a menu's entries carry no identifiers.
    @MainActor
    private func remove(times: Int, with remote: XCUIRemote) {
        remote.press(.select, forDuration: 1.5)
        for _ in 0..<times {
            remote.press(.down)
        }
        remote.press(.select)
    }

    @MainActor
    private func waitForFocus(on element: XCUIElement) {
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: element)
        wait(for: [focused], timeout: 10)
    }
}
