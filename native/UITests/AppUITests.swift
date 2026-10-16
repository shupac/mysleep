import XCTest

final class AppUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testDemoReportAndSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["SLEEP SCORE"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Total sleep 7h 30m"].exists)
        app.swipeUp()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.textFields["email"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["password"].exists)
        XCTAssertFalse(app.staticTexts["Worker connection"].exists)
    }
    func testOfflineReportIsClearlyLabeled() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-stale"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Offline · saved report"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Total sleep 7h 30m"].exists)
    }
    func testOnboardingWithoutCredentials() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-empty"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Your sleep, at a glance"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Sign in to Eight Sleep in Settings."].exists)
        XCTAssertFalse(app.staticTexts["SLEEP SCORE"].exists)
    }
}

extension AppUITests {
    func testPodControlsApplyTemperatureAndConfirmEndSleepInDemo() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        let controls = app.buttons["podControls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 10))
        controls.tap()
        let apply = app.buttons["applyTemperature"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        let temperature = app.sliders["temperatureFahrenheit"]
        XCTAssertTrue(temperature.exists)
        XCTAssertTrue(app.staticTexts["76°F"].exists)
        temperature.adjust(toNormalizedSliderPosition: 0.5)
        apply.tap()
        XCTAssertTrue(app.staticTexts["Demo only. No Pod command was sent."].waitForExistence(timeout: 5))
        let end = app.buttons["endSleep"]
        if !end.isHittable { app.swipeUp() }
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        end.tap()
        let confirmation = app.buttons["End sleep and process report"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()
        XCTAssertTrue(app.buttons["endSleep"].exists)
        XCTAssertTrue(app.staticTexts["Demo only. No Pod command was sent."].exists)
    }
}
