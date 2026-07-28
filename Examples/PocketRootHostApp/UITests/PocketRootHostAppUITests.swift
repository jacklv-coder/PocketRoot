import XCTest

@MainActor
final class PocketRootHostAppUITests: XCTestCase {
    func testPTYCommandCreatesFileVisibleInFiles() {
        let app = launchAndBoot()

        let terminalButton = app.buttons["PocketRootHost.terminal"]
        terminalButton.tap()

        let terminal = terminalElement(in: app)
        XCTAssertTrue(terminal.waitForExistence(timeout: 30))
        terminal.tap()
        terminal.typeText(
            "rm -rf /root/pocketroot-ui-smoke; "
                + "mkdir -p /root/pocketroot-ui-smoke; "
                + "printf 'PocketRoot UI smoke\\n' "
                + "> /root/pocketroot-ui-smoke/created.txt; exit\n"
        )

        let exitedNavigationBar = app.navigationBars["Terminal Exited (0)"]
        XCTAssertTrue(exitedNavigationBar.waitForExistence(timeout: 30))
        exitedNavigationBar.buttons.element(boundBy: 0).tap()

        let filesButton = app.buttons["PocketRootHost.files"]
        XCTAssertTrue(filesButton.waitForExistence(timeout: 10))
        filesButton.tap()

        let directory = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/pocketroot-ui-smoke"
        ]
        XCTAssertTrue(directory.waitForExistence(timeout: 30))
        directory.tap()

        let file = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/pocketroot-ui-smoke/created.txt"
        ]
        XCTAssertTrue(file.waitForExistence(timeout: 30))
        file.tap()

        let preview = app.staticTexts["PocketRootFiles.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 30))
        XCTAssertEqual(preview.label, "PocketRoot UI smoke\n")
    }

    func testPTYLifecycleAndShutdown() {
        addTeardownBlock {
            XCUIDevice.shared.orientation = .portrait
        }

        let app = launchAndBoot()
        let terminalButton = app.buttons["PocketRootHost.terminal"]
        terminalButton.tap()

        var terminal = terminalElement(in: app)
        XCTAssertTrue(terminal.waitForExistence(timeout: 30))
        terminal.tap()
        terminal.typeText(
            "rm -rf /root/pocketroot-device-ui-smoke; "
                + "mkdir -p /root/pocketroot-device-ui-smoke; "
                + "printf 'before-background\\n' "
                + "> /root/pocketroot-device-ui-smoke/lifecycle.txt\n"
        )
        allowTerminalToDrain()

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 15))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        terminal = terminalElement(in: app)
        XCTAssertTrue(terminal.waitForExistence(timeout: 30))
        terminal.tap()
        terminal.typeText(
            "seq 1 128; "
                + "printf 'after-foreground\\n' "
                + ">> /root/pocketroot-device-ui-smoke/lifecycle.txt\n"
        )
        allowTerminalToDrain()

        XCUIDevice.shared.orientation = .landscapeLeft
        allowTerminalToDrain()
        XCTAssertTrue(terminalElement(in: app).exists)
        XCUIDevice.shared.orientation = .portrait
        allowTerminalToDrain()
        XCTAssertTrue(terminalElement(in: app).exists)

        tapBackButton(in: app)
        XCTAssertTrue(terminalButton.waitForExistence(timeout: 30))
        wait(
            for: NSPredicate(format: "enabled == true"),
            evaluatedWith: terminalButton,
            timeout: 10
        )

        terminalButton.tap()
        terminal = terminalElement(in: app)
        XCTAssertTrue(terminal.waitForExistence(timeout: 30))
        terminal.tap()
        terminal.typeText(
            "printf 'after-reopen\\n' "
                + ">> /root/pocketroot-device-ui-smoke/lifecycle.txt; exit\n"
        )

        let exitedNavigationBar = app.navigationBars["Terminal Exited (0)"]
        XCTAssertTrue(exitedNavigationBar.waitForExistence(timeout: 30))
        exitedNavigationBar.buttons.element(boundBy: 0).tap()

        let filesButton = app.buttons["PocketRootHost.files"]
        XCTAssertTrue(filesButton.waitForExistence(timeout: 10))
        filesButton.tap()

        let directory = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/pocketroot-device-ui-smoke"
        ]
        XCTAssertTrue(directory.waitForExistence(timeout: 30))
        directory.tap()

        let file = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/pocketroot-device-ui-smoke/lifecycle.txt"
        ]
        XCTAssertTrue(file.waitForExistence(timeout: 30))
        file.tap()

        let preview = app.staticTexts["PocketRootFiles.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 30))
        XCTAssertEqual(
            preview.label,
            "before-background\nafter-foreground\nafter-reopen\n"
        )

        returnToHost(in: app)
        let shutdownButton = app.buttons["PocketRootHost.shutdown"]
        XCTAssertTrue(shutdownButton.waitForExistence(timeout: 30))
        shutdownButton.tap()

        let status = app.staticTexts["PocketRootHost.status"]
        wait(
            for: NSPredicate(format: "label == %@", "Runtime: Restart App"),
            evaluatedWith: status,
            timeout: 30
        )
        XCTAssertFalse(terminalButton.isEnabled)
        XCTAssertFalse(filesButton.isEnabled)
        XCTAssertFalse(shutdownButton.isEnabled)
    }

    private func launchAndBoot() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-PocketRootUITesting"
        ]
        app.launch()

        let status = app.staticTexts["PocketRootHost.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Runtime: Ready to Boot")

        let bootButton = app.buttons["PocketRootHost.boot"]
        XCTAssertTrue(bootButton.waitForExistence(timeout: 10))
        bootButton.tap()
        wait(
            for: NSPredicate(format: "label == %@", "Runtime: Ready"),
            evaluatedWith: status,
            timeout: 90
        )

        let terminalButton = app.buttons["PocketRootHost.terminal"]
        wait(
            for: NSPredicate(format: "enabled == true"),
            evaluatedWith: terminalButton,
            timeout: 10
        )
        return app
    }

    private func terminalElement(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["PocketRootTerminal.pty"]
    }

    private func tapBackButton(in app: XCUIApplication) {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 10))
        backButton.tap()
    }

    private func returnToHost(in app: XCUIApplication) {
        let status = app.staticTexts["PocketRootHost.status"]
        for _ in 0..<4 where !status.exists {
            tapBackButton(in: app)
        }
        XCTAssertTrue(status.waitForExistence(timeout: 10))
    }

    private func allowTerminalToDrain() {
        RunLoop.current.run(until: Date().addingTimeInterval(1))
    }

    private func wait(
        for predicate: NSPredicate,
        evaluatedWith object: Any,
        timeout: TimeInterval
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: object
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed
        )
    }
}
