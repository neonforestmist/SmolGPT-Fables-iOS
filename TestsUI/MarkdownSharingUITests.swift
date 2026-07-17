import XCTest

final class MarkdownSharingUITests: XCTestCase {
    func testNormalLaunchLoadsInstalledModel() {
        let app = XCUIApplication()
        app.launch()

        let status = app.descendants(matching: .any)["model-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let ready = app.staticTexts["Ready. Generation stays on this device."]
        XCTAssertTrue(
            ready.waitForExistence(timeout: 90),
            "The normally installed app should load its Core ML model successfully. Current status: \(status.label)"
        )
    }

    func testShareMarkdownOpensSystemShareSheet() {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-test-markdown-share")
        app.launch()

        let output = app.descendants(matching: .any)["story-markdown-output"]
        XCTAssertTrue(output.waitForExistence(timeout: 5))

        let share = app.descendants(matching: .any)["share-markdown"]
        for _ in 0..<8 where !share.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        XCTAssertTrue(share.isHittable)

        share.tap()

        let activityList = app.otherElements["ActivityListView"]
        let copyAction = app.buttons["Copy"]
        XCTAssertTrue(
            activityList.waitForExistence(timeout: 5)
                || copyAction.waitForExistence(timeout: 2),
            "Tapping Share Markdown should present the system share sheet."
        )
    }

    func testNormalAppGeneratesTitledMarkdown() {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-test-live-generation")
        app.launch()

        let ready = app.staticTexts["Ready. Generation stays on this device."]
        XCTAssertTrue(ready.waitForExistence(timeout: 90))

        let write = app.buttons["Write my story"]
        for _ in 0..<10 where !write.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(write.waitForExistence(timeout: 5))
        XCTAssertTrue(write.isHittable)
        write.tap()

        let title = app.staticTexts["A SmolGPT Fable"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 60),
            "The reader output should show the Markdown document title."
        )
        let sceneHeading = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Scene 01")
        ).firstMatch
        XCTAssertTrue(
            sceneHeading.waitForExistence(timeout: 60),
            "The reader output should show the generated Scene 01 heading."
        )
        let generatedProse = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "quiet forest")
        ).firstMatch
        XCTAssertTrue(
            generatedProse.waitForExistence(timeout: 60),
            "The real Core ML output should render story prose below the scene heading."
        )
        let share = app.descendants(matching: .any)["share-markdown"]
        for _ in 0..<6 where !share.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(share.waitForExistence(timeout: 60))
        XCTAssertTrue(share.isHittable)
    }

    func testCaptureThreeSceneGallery() throws {
        guard ProcessInfo.processInfo.environment["CAPTURE_RELEASE_SCREENSHOTS"] == "1" else {
            throw XCTSkip("Set CAPTURE_RELEASE_SCREENSHOTS=1 to create the README gallery.")
        }

        let app = XCUIApplication()
        app.launchArguments.append("-ui-test-markdown-share")
        app.launch()

        let firstScene = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Scene 01")
        ).firstMatch
        XCTAssertTrue(firstScene.waitForExistence(timeout: 5))
        for _ in 0..<12 where !firstScene.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(firstScene.isHittable)
        let beginningScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        beginningScreenshot.name = "three-scene-story-beginning"
        beginningScreenshot.lifetime = .keepAlways
        add(beginningScreenshot)

        let thirdScene = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Scene 03")
        ).firstMatch
        XCTAssertTrue(thirdScene.waitForExistence(timeout: 5))
        for _ in 0..<12 where !thirdScene.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(thirdScene.isHittable)

        let completedScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        completedScreenshot.name = "three-scene-story-ending"
        completedScreenshot.lifetime = .keepAlways
        add(completedScreenshot)
    }
}
