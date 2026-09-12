import XCTest

final class CaptureUITests: XCTestCase {
    func testCaptureScreenAndConnectionValidation() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Capture song"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        let endpoint = app.textFields["Capture URL"]
        XCTAssertTrue(endpoint.waitForExistence(timeout: 3))
        endpoint.tap()
        endpoint.typeText("http://example.com/capture")
        let token = app.secureTextFields["Access token"]
        token.tap()
        token.typeText("test-token")
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
}
