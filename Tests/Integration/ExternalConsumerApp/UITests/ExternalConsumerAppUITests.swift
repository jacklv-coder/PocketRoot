import XCTest

@MainActor
final class ExternalConsumerAppUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testRemoteConsumerTerminalFilesAndLifecycleClosure() {
        let app = launchApp()
        let terminalButton = app.buttons["ExternalConsumer.terminal"]
        XCTAssertTrue(terminalButton.waitForExistence(timeout: 10))
        XCTAssertTrue(terminalButton.isEnabled)
        terminalButton.tap()

        let terminal = app.descendants(matching: .any)[
            "PocketRootTerminal.pty"
        ]
        XCTAssertTrue(terminal.waitForExistence(timeout: 90))
        terminal.tap()

        let suffix = String(UUID().uuidString.prefix(8)).lowercased()
        let fileName = "external-consumer-\(suffix).txt"
        let contents = "PocketRoot external consumer closure"
        let marker = "__POCKETROOT_EXTERNAL_CONSUMER_CREATED__"
        terminal.typeText(
            "printf '\(contents)\\n' > /root/\(fileName); "
                + "sync; printf '\(marker)\\n'\n"
        )
        wait(
            for: NSPredicate(format: "value CONTAINS %@", marker),
            evaluatedWith: terminal,
            timeout: 30
        )
        dismissKeyboard(in: app)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 15))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        XCTAssertTrue(terminal.waitForExistence(timeout: 30))
        let foregroundMarker =
            "__POCKETROOT_EXTERNAL_CONSUMER_FOREGROUND__"
        terminal.tap()
        terminal.typeText("printf '\(foregroundMarker)\\n'\n")
        wait(
            for: NSPredicate(
                format: "value CONTAINS %@",
                foregroundMarker
            ),
            evaluatedWith: terminal,
            timeout: 30
        )
        dismissKeyboard(in: app)
        tapFirstBackButton(in: app, navigationBarTitle: "Terminal")

        let filesButton = app.buttons["ExternalConsumer.files"]
        XCTAssertTrue(filesButton.waitForExistence(timeout: 30))
        XCTAssertTrue(filesButton.isEnabled)
        filesButton.tap()

        let file = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/\(fileName)"
        ]
        XCTAssertTrue(file.waitForExistence(timeout: 90))
        file.tap()

        let preview = app.staticTexts["PocketRootFiles.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 30))
        XCTAssertEqual(preview.label, "\(contents)\n")

        tapFirstBackButton(in: app, navigationBarTitle: fileName)
        tapFirstBackButton(in: app, navigationBarTitle: "root")

        let shutdownButton = app.buttons["ExternalConsumer.shutdown"]
        XCTAssertTrue(shutdownButton.waitForExistence(timeout: 30))
        wait(
            for: NSPredicate(format: "enabled == true"),
            evaluatedWith: shutdownButton,
            timeout: 30
        )
        shutdownButton.tap()

        let status = app.staticTexts["ExternalConsumer.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        wait(
            for: NSPredicate(format: "label == %@", "Runtime Terminated"),
            evaluatedWith: status,
            timeout: 90
        )
        XCTAssertFalse(terminalButton.isEnabled)
        XCTAssertFalse(filesButton.isEnabled)
        XCTAssertFalse(shutdownButton.isEnabled)
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-PocketRootUITesting"
        ]
        app.launch()
        return app
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        let keyboard = app.keyboards.element
        for _ in 0..<3 where keyboard.exists {
            let continueButton = app.buttons["Continue"]
            if continueButton.exists {
                continueButton.tap()
            } else {
                let hideKeyboardButton = app.buttons["hide keyboard"]
                XCTAssertTrue(
                    hideKeyboardButton.waitForExistence(timeout: 10)
                )
                hideKeyboardButton.tap()
            }
            RunLoop.current.run(
                until: Date().addingTimeInterval(0.5)
            )
        }
        XCTAssertFalse(keyboard.exists)
    }

    private func tapFirstBackButton(
        in app: XCUIApplication,
        navigationBarTitle: String
    ) {
        let navigationBar = app.navigationBars[navigationBarTitle]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 10))
        let backButton = navigationBar.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 10))
        backButton.tap()
    }

    @discardableResult
    private func wait(
        for predicate: NSPredicate,
        evaluatedWith object: Any,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: object
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(
            result,
            .completed,
            "predicate \(predicate) to become true",
            file: file,
            line: line
        )
        return result == .completed
    }
}
