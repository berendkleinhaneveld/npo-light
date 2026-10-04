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

    // Requirement: FR-CONTENT-03, FR-CONTENT-07, FR-CONTENT-08
    @MainActor
    func testSeriesIsBrowsedOneSeasonAtATime() throws {
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

        // From the keyboard down to the first result, and into it.
        remote.press(.down)
        remote.press(.select)

        // The page opens on the first season, with its episodes and a preview.
        let firstSeason = app.buttons["season-season-1"]
        let secondSeason = app.buttons["season-season-2"]
        XCTAssertTrue(firstSeason.waitForExistence(timeout: 10))
        XCTAssertTrue(firstSeason.isSelected)
        XCTAssertTrue(app.buttons["episode-season-1-episode-1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["episode-preview"].exists)

        // The page opens on the series itself; down goes into its seasons,
        // on the one being shown.
        remote.press(.down)
        XCTAssertTrue(firstSeason.hasFocus)

        // Moving along the picker shows the next season without a press.
        remote.press(.right)
        XCTAssertTrue(app.buttons["episode-season-2-episode-1"].waitForExistence(timeout: 10))
        XCTAssertTrue(secondSeason.isSelected)
        XCTAssertFalse(app.buttons["episode-season-1-episode-1"].exists)

        // Down into the list and back up lands on the season being shown.
        remote.press(.down)
        XCTAssertTrue(app.buttons["episode-season-2-episode-1"].hasFocus)
        remote.press(.up)
        XCTAssertTrue(secondSeason.hasFocus)
        XCTAssertTrue(app.buttons["episode-season-2-episode-1"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Series detail"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // Requirement: FR-CONTENT-07, NFR-A11Y-01
    @MainActor
    func testFocusFollowsTheShownSeason() throws {
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
        let firstSeason = app.buttons["season-season-1"]
        XCTAssertTrue(firstSeason.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["episode-season-1-episode-1"].waitForExistence(timeout: 10))
        remote.press(.down)
        remote.press(.right)
        XCTAssertTrue(app.buttons["episode-season-2-episode-1"].waitForExistence(timeout: 10))
        // The page moved to its seasons and stays there when focus goes
        // along them: the picker is at the top of the screen, not a row down.
        XCTAssertLessThan(firstSeason.frame.minY, 120)

        // Into the second season's list and back out.
        let secondSeason = app.buttons["season-season-2"]
        remote.press(.down)
        remote.press(.down)
        XCTAssertTrue(app.buttons["episode-season-2-episode-2"].hasFocus)
        remote.press(.up)
        remote.press(.up)
        XCTAssertTrue(secondSeason.hasFocus)

        // Back on a season already seen, its own list takes focus: not the
        // rows of the list that was there a moment ago.
        remote.press(.left)
        XCTAssertTrue(firstSeason.hasFocus)
        let firstEpisode = app.buttons["episode-season-1-episode-1"]
        XCTAssertTrue(firstEpisode.waitForExistence(timeout: 10))
        remote.press(.down)
        XCTAssertTrue(firstEpisode.hasFocus)

        // Up lands on the season being shown, not on the one that happens to
        // be above the middle of the list, and the list stays as it is.
        remote.press(.up)
        XCTAssertTrue(firstSeason.hasFocus)
        XCTAssertTrue(firstSeason.isSelected)
        XCTAssertTrue(firstEpisode.exists)

        // The same from the last season.
        let thirdSeason = app.buttons["season-season-3"]
        remote.press(.right)
        remote.press(.right)
        XCTAssertTrue(app.buttons["episode-season-3-episode-1"].waitForExistence(timeout: 10))
        remote.press(.down)
        XCTAssertTrue(app.buttons["episode-season-3-episode-1"].hasFocus)
        remote.press(.up)
        XCTAssertTrue(thirdSeason.hasFocus)
        XCTAssertTrue(thirdSeason.isSelected)
    }

    // Requirement: FR-SEARCH-04, FR-SEARCH-05, FR-SEARCH-07
    @MainActor
    func testRecentSearchesAreKeptAndCleared() throws {
        let app = XCUIApplication()
        let remote = XCUIRemote.shared
        app.launchEnvironment["NPO_LIGHT_SCENARIO"] = "signed-in"
        app.launch()
        XCTAssertTrue(app.buttons["home-search"].waitForExistence(timeout: 10))
        remote.press(.select)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))

        // With no history the page says so.
        XCTAssertTrue(app.staticTexts["search-no-history"].waitForExistence(timeout: 10))

        // Open a series from the results, and come back.
        field.typeText("fr")
        XCTAssertTrue(app.buttons["Freeks wilde wereld, serie"].waitForExistence(timeout: 10))
        remote.press(.down)
        remote.press(.select)
        XCTAssertTrue(app.buttons["season-season-1"].waitForExistence(timeout: 10))
        remote.press(.menu)
        XCTAssertTrue(app.buttons["Freeks wilde wereld, serie"].waitForExistence(timeout: 10))

        // Emptying the field shows the term, with what was picked for it.
        remote.press(.up)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        XCTAssertTrue(app.buttons["recent-term-fr"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["recent-pick-series-1"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Recent searches"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Clearing asks first, and then the page is empty again.
        let clear = app.buttons["search-clear-history"]
        for _ in 0..<4 where !clear.hasFocus {
            remote.press(.down)
        }
        XCTAssertTrue(clear.hasFocus)
        remote.press(.select)
        // The dialog opens on its cancel button; the one that clears is the
        // one carrying the same label as the identified action.
        let confirm = app.buttons["search-clear-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        let clearing = app.buttons.matching(NSPredicate(format: "label == %@", confirm.label))
        func clearingHasFocus() -> Bool {
            clearing.allElementsBoundByIndex.contains { $0.hasFocus }
        }
        XCTAssertFalse(clearingHasFocus())
        remote.press(.right)
        XCTAssertTrue(clearingHasFocus())
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["search-no-history"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["recent-term-fr"].exists)
    }

    // Requirement: FR-HOME-02, FR-HOME-03, FR-HOME-05, FR-HOME-09, FR-HOME-10
    @MainActor
    func testSeriesIsPinnedAndUnpinned() throws {
        let app = XCUIApplication()
        let remote = XCUIRemote.shared
        app.launchEnvironment["NPO_LIGHT_SCENARIO"] = "signed-in"
        app.launch()

        // Nothing pinned: the row says what to do.
        XCTAssertTrue(app.buttons["home-search"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["pinned-empty-search"].exists)

        // Find a series, and pin it from its page.
        remote.press(.select)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText("fr")
        XCTAssertTrue(app.buttons["Freeks wilde wereld, serie"].waitForExistence(timeout: 10))
        remote.press(.down)
        remote.press(.select)
        let pin = app.buttons["series-pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["season-season-1"].waitForExistence(timeout: 10))
        for _ in 0..<3 where !pin.hasFocus {
            remote.press(.up)
        }
        XCTAssertTrue(pin.hasFocus)
        remote.press(.select)
        XCTAssertTrue(app.buttons["series-unpin"].waitForExistence(timeout: 10))

        // Back home, the series is on the row without a refresh.
        remote.press(.menu)
        remote.press(.menu)
        let tile = app.buttons["pinned-series-1"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["pinned-empty-search"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Home with a pin"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Its tile opens the series, where it can be unpinned again.
        for _ in 0..<3 where !tile.hasFocus {
            remote.press(.down)
        }
        XCTAssertTrue(tile.hasFocus)
        remote.press(.select)
        let unpin = app.buttons["series-unpin"]
        XCTAssertTrue(unpin.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["season-season-1"].waitForExistence(timeout: 10))
        for _ in 0..<3 where !unpin.hasFocus {
            remote.press(.up)
        }
        remote.press(.select)
        XCTAssertTrue(app.buttons["series-pin"].waitForExistence(timeout: 10))
        remote.press(.menu)
        XCTAssertTrue(app.buttons["pinned-empty-search"].waitForExistence(timeout: 10))
    }

    // Requirement: FR-CONTENT-08, NFR-A11Y-01
    @MainActor
    func testLastEpisodeOfASeasonCanBeReached() throws {
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

        // Into the seasons, down the whole season, which is longer than the
        // screen, and once more: focus is on the last episode and stays there.
        let last = app.buttons["episode-season-1-episode-12"]
        for _ in 0..<14 {
            remote.press(.down)
        }
        XCTAssertTrue(last.hasFocus)
        XCTAssertTrue(app.buttons["episode-season-1-episode-1"].exists)
    }
}
