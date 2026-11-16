//
//  SearchUITests.swift
//  NPO lightUITests
//

import XCTest

final class SearchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // Requirement: FR-SEARCH-01, FR-SEARCH-11
    @MainActor
    func testSearchStartsEmptyFromHome() throws {
        let app = XCUIApplication()
        let remote = XCUIRemote.shared
        app.launchEnvironment["NPO_LIGHT_SCENARIO"] = "signed-in"
        app.launch()
        let search = app.buttons["home-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        // The page opens on its way to search, also with two empty rows that
        // each offer one of their own.
        waitForFocus(on: search)
        remote.press(.select)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText("fr")
        let result = app.buttons["Freeks wilde wereld, serie"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))

        // From the results back to home, and into search again.
        remote.press(.down)
        remote.press(.menu)
        XCTAssertTrue(field.waitForNonExistence(timeout: 10))
        // Focus is back where search was opened from.
        waitForFocus(on: search)
        remote.press(.select)

        // The field is empty: the term is among the recent searches, and its
        // results are not on screen.
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["recent-term-fr"].waitForExistence(timeout: 10))
        XCTAssertFalse(result.exists)
    }

    @MainActor
    private func waitForFocus(on element: XCUIElement) {
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: element)
        wait(for: [focused], timeout: 10)
    }
}
