import XCTest

@MainActor
final class PocketRootHostAppUITests: XCTestCase {
    func testPTYCommandCreatesFileVisibleInFiles() {
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
        terminalButton.tap()

        let terminal = app.descendants(matching: .any)["PocketRootTerminal.pty"]
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
