//
//  SearchUITests.swift
//  NPO lightUITests
//

import XCTest

final class SearchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // Requirement: FR-SEARCH-11
    @MainActor
    func testSearchStartsEmptyFromHome() throws {
        let app = XCUIApplication()
        let remote = XCUIRemote.shared
        app.launchEnvironment["NPO_LIGHT_SCENARIO"] = "signed-in"
        app.launch()
        let search = app.buttons["home-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
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
        let ways = [search, app.buttons["pinned-empty-search"]]
        XCTAssertTrue(ways.contains(where: \.hasFocus), "Focus is not on a way to search")
        remote.press(.select)

        // The field is empty: the term is among the recent searches, and its
        // results are not on screen.
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["recent-term-fr"].waitForExistence(timeout: 10))
        XCTAssertFalse(result.exists)
    }
}
