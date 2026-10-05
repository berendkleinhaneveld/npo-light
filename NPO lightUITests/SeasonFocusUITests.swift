//
//  SeasonFocusUITests.swift
//  NPO lightUITests
//

import XCTest

final class SeasonFocusUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // Requirement: FR-CONTENT-07, NFR-A11Y-01
    @MainActor
    func testEpisodesAreReachedFromAFarSeason() throws {
        let app = XCUIApplication()
        let remote = XCUIRemote.shared
        app.launchEnvironment["NPO_LIGHT_SCENARIO"] = "signed-in"
        app.launch()
        XCTAssertTrue(app.buttons["home-search"].waitForExistence(timeout: 10))
        remote.press(.select)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText("fr")
        XCTAssertTrue(app.buttons["Freeks wilde wereld, serie"].waitForExistence(timeout: 10))
        remote.press(.down)
        remote.press(.select)
        XCTAssertTrue(app.buttons["episode-season-1-episode-1"].waitForExistence(timeout: 10))

        // Along the picker to a season that is not above the list of
        // episodes: down still goes into its episodes, and up comes back.
        let lastSeason = app.buttons["season-season-7"]
        remote.press(.down)
        for _ in 0..<6 {
            remote.press(.right)
        }
        XCTAssertTrue(lastSeason.hasFocus)
        let firstEpisode = app.buttons["episode-season-7-episode-1"]
        XCTAssertTrue(firstEpisode.waitForExistence(timeout: 10))
        remote.press(.down)
        XCTAssertTrue(firstEpisode.hasFocus)
        remote.press(.up)
        XCTAssertTrue(lastSeason.hasFocus)
    }
}
