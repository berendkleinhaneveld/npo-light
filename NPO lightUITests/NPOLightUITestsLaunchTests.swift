//
//  NPOLightUITestsLaunchTests.swift
//  NPO lightUITests
//
//  Created by Berend Klein Haneveld on 29/08/2026.
//

import XCTest

final class NPOLightUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a
        // screenshot, such as logging into a test account or navigating somewhere.

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
