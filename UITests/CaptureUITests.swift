import XCTest

final class CaptureUITests: XCTestCase {
    func testAccidentalCaptureCanBeCanceledAndStartedAgain() {
        let app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Native capture permissions") { alert in
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }
            if alert.buttons["OK"].exists { alert.buttons["OK"].tap(); return true }
            return false
        }
        app.launch()
        let capture = app.buttons["Capture song"]
        XCTAssertTrue(capture.waitForExistence(timeout: 5))
        capture.tap()
        // A harmless interaction lets the interruption monitor dismiss the microphone prompt.
        app.navigationBars.firstMatch.tap()
        let cancel = app.buttons["Cancel capture"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(app.staticTexts["Capture canceled."].waitForExistence(timeout: 3))
        XCTAssertTrue(capture.waitForExistence(timeout: 3))
        capture.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        let listening = XCTAttachment(screenshot: app.screenshot())
        listening.name = "Cancellable recording"
        listening.lifetime = .keepAlways
        add(listening)
        cancel.tap()
        XCTAssertTrue(capture.waitForExistence(timeout: 3))
    }

    func testSavedConnectionIsRestoredAfterRelaunch() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Settings"].tap()
        let endpoint = app.textFields["Capture URL"]
        XCTAssertTrue(endpoint.waitForExistence(timeout: 3))
        replaceText(in: endpoint, with: "https://example.invalid/capture", app: app)
        let token = app.textFields["Access token"]
        replaceText(in: token, with: "test-token", app: app)
        app.buttons["Save connection"].tap()
        XCTAssertTrue(app.staticTexts["Connection saved on this iPhone."].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        app.terminate()
        app.launch()
        app.buttons["Settings"].tap()
        XCTAssertTrue(endpoint.waitForExistence(timeout: 3))
        XCTAssertEqual(endpoint.value as? String, "https://example.invalid/capture")
        XCTAssertTrue(app.staticTexts["Connection saved on this iPhone."].waitForExistence(timeout: 3))
    }

    func testCaptureScreenAndConnectionValidation() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Capture song"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        let endpoint = app.textFields["Capture URL"]
        XCTAssertTrue(endpoint.waitForExistence(timeout: 3))
        replaceText(in: endpoint, with: "http://example.com/capture", app: app)
        let token = app.textFields["Access token"]
        replaceText(in: token, with: "test-token", app: app)
        app.buttons["Save connection"].tap()
        XCTAssertTrue(app.staticTexts["Enter the HTTPS capture URL from Music Sync, without login details or query parameters."].waitForExistence(timeout: 3))
        let settings = XCTAttachment(screenshot: app.screenshot())
        settings.name = "Connection validation"
        settings.lifetime = .keepAlways
        add(settings)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Capture song"].isHittable)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Capture screen"
        capture.lifetime = .keepAlways
        add(capture)
    }

    private func replaceText(in field: XCUIElement, with value: String, app: XCUIApplication) {
        field.tap()
        if let existing = field.value as? String, !existing.isEmpty, existing != field.placeholderValue {
            field.press(forDuration: 1)
            let selectAll = app.menuItems["Select All"]
            if selectAll.waitForExistence(timeout: 2) { selectAll.tap() }
            else if app.buttons["Select All"].exists { app.buttons["Select All"].tap() }
            else { field.tap(withNumberOfTaps: 3, numberOfTouches: 1) }
        }
        field.typeText(value)
        if field.elementType == .textField { XCTAssertEqual(field.value as? String, value) }
    }
}
