import XCTest

@MainActor
final class PocketRootQuickStartAppUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testFilesEntryAutoBootsFromColdLaunch() {
        let app = launchApp()
        let filesButton = app.buttons["PocketRootQuickStart.files"]
        XCTAssertTrue(filesButton.waitForExistence(timeout: 10))
        XCTAssertTrue(filesButton.isEnabled)
        filesButton.tap()

        let actions = app.buttons["PocketRootFiles.actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 90))
        XCTAssertTrue(actions.isEnabled)
    }

    func testTerminalCreatesFileThatFilesCanPreview() {
        let app = launchApp()
        let terminalButton = app.buttons["PocketRootQuickStart.terminal"]
        XCTAssertTrue(terminalButton.waitForExistence(timeout: 10))
        XCTAssertTrue(terminalButton.isEnabled)
        terminalButton.tap()

        let terminal = app.descendants(matching: .any)[
            "PocketRootTerminal.pty"
        ]
        XCTAssertTrue(terminal.waitForExistence(timeout: 90))
        terminal.tap()

        let suffix = String(UUID().uuidString.prefix(8)).lowercased()
        let fileName = "quick-start-\(suffix).txt"
        let contents = "PocketRoot Quick Start UI closure"
        let marker = "__POCKETROOT_QUICK_START_CREATED__"
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
        tapBackButton(in: app)

        let filesButton = app.buttons["PocketRootQuickStart.files"]
        XCTAssertTrue(filesButton.waitForExistence(timeout: 30))
        filesButton.tap()

        let file = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/\(fileName)"
        ]
        XCTAssertTrue(file.waitForExistence(timeout: 90))
        file.tap()

        let preview = app.staticTexts["PocketRootFiles.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 30))
        XCTAssertEqual(preview.label, "\(contents)\n")
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

    private func tapBackButton(in app: XCUIApplication) {
        let navigationBar = app.navigationBars["Terminal"]
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
