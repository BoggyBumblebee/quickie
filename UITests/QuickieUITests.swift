import Carbon
import XCTest

final class QuickieUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSettingsWindowShowsShortcutControls() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting-show-settings",
            "--uitesting-reset-shortcut-default"
        ]

        app.launch()

        let settingsWindow = app.windows["Quickie Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.shortcutRecorder"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Reset to Default"].exists)
        XCTAssertTrue(app.buttons["Help"].exists)
        XCTAssertTrue(app.buttons["Quit Quickie"].exists)
    }

    @MainActor
    func testSettingsWindowShowsDetailedRegistrationError() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting-show-settings",
            "--uitesting-reset-shortcut-default",
            "--uitesting-registration-status=\(eventHotKeyExistsErr)"
        ]

        app.launch()

        let settingsWindow = app.windows["Quickie Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))

        let warningText = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "eventHotKeyExistsErr")
        ).firstMatch

        XCTAssertTrue(warningText.waitForExistence(timeout: 2))
        XCTAssertTrue(warningText.label.contains("OSStatus \(eventHotKeyExistsErr)"))
    }

    @MainActor
    func testShortcutRecorderUpdatesDisplayedShortcut() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting-show-settings",
            "--uitesting-reset-shortcut-default"
        ]

        app.launch()

        let recorder = app.buttons["settings.shortcutRecorder"]
        XCTAssertTrue(recorder.waitForExistence(timeout: 5))

        recorder.click()
        recorder.typeKey("n", modifierFlags: [.command, .shift])

        XCTAssertTrue(recorder.waitForExistence(timeout: 2))
        XCTAssertEqual(recorder.label, "⇧⌘N")
    }
}
