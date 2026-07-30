import XCTest

@MainActor
final class PocketRootHostAppUITests: XCTestCase {
    private static let systemImportFixtureName =
        "pocketroot-system-file-ui-fixture.txt"
    private static let systemImportFixtureDisplayName =
        "pocketroot-system-file-ui-fixture"
    private static let systemFixtureContents =
        "PocketRoot system file transfer UI fixture\n"

    func testFilesCreateAndDelete() {
        let app = launchAndBoot()
        app.buttons["PocketRootHost.files"].tap()

        let suffix = String(UUID().uuidString.prefix(8)).lowercased()
        let fileName = "files-\(suffix).txt"
        let renamedFileName = "\(fileName).renamed"
        let folderName = "folder-\(suffix)"
        let nestedFileName = "nested-\(suffix).txt"
        let actions = app.buttons["PocketRootFiles.actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 30))
        waitForEnabled(actions)

        actions.tap()
        XCTAssertTrue(app.buttons["Import File"].waitForExistence(timeout: 10))
        app.buttons["New File"].tap()
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.typeText(fileName)
        app.buttons["Create"].tap()

        let file = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/\(fileName)"
        ]
        XCTAssertTrue(file.waitForExistence(timeout: 30))
        waitForEnabled(file)
        file.press(forDuration: 1)
        XCTAssertTrue(
            app.buttons["Share / Export"].waitForExistence(timeout: 10)
        )
        app.buttons["Rename"].tap()
        let renameAlert = app.alerts["Rename"]
        XCTAssertTrue(renameAlert.waitForExistence(timeout: 10))
        let renameNameField = renameAlert.textFields["Name"]
        XCTAssertTrue(renameNameField.waitForExistence(timeout: 10))
        XCTAssertEqual(renameNameField.value as? String, fileName)
        renameNameField.coordinate(
            withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)
        ).tap()
        renameNameField.typeText(".renamed")
        XCTAssertEqual(renameNameField.value as? String, renamedFileName)
        renameAlert.buttons["Rename"].tap()

        let renamedFile = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/\(renamedFileName)"
        ]
        XCTAssertTrue(renamedFile.waitForExistence(timeout: 30))
        wait(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: file,
            timeout: 30
        )
        waitForEnabled(renamedFile)
        renamedFile.press(forDuration: 1)
        app.buttons["Delete"].tap()
        confirmDeletion(of: renamedFileName, in: app)
        wait(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: renamedFile,
            timeout: 30
        )

        waitForEnabled(actions)
        actions.tap()
        app.buttons["New Folder"].tap()
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.typeText(folderName)
        app.buttons["Create"].tap()

        let folder = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/\(folderName)"
        ]
        XCTAssertTrue(folder.waitForExistence(timeout: 30))
        let disclosure = app.buttons[
            "PocketRootFiles.disclosure./root/\(folderName)"
        ]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 10))
        waitForEnabled(disclosure)
        disclosure.tap()
        waitForEnabled(folder)
        folder.tap()

        waitForEnabled(actions)
        actions.tap()
        app.buttons["New File"].tap()
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.typeText(nestedFileName)
        app.buttons["Create"].tap()
        waitForEnabled(actions)
        let childNavigationBar = app.navigationBars[folderName]
        XCTAssertTrue(childNavigationBar.waitForExistence(timeout: 10))
        childNavigationBar.buttons.element(boundBy: 0).tap()

        let nestedFile = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/\(folderName)/\(nestedFileName)"
        ]
        XCTAssertTrue(nestedFile.waitForExistence(timeout: 30))
        folder.press(forDuration: 1)
        app.buttons["Delete"].tap()
        confirmDeletion(of: folderName, in: app)
        wait(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: folder,
            timeout: 30
        )
    }

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

        let disclosure = app.buttons[
            "PocketRootFiles.disclosure./root/pocketroot-ui-smoke"
        ]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 10))
        disclosure.tap()

        let inlineFile = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/pocketroot-ui-smoke/created.txt"
        ]
        XCTAssertTrue(inlineFile.waitForExistence(timeout: 30))
        XCTAssertTrue(app.navigationBars["root"].exists)

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

    func testSystemFileImportAndShareExportRoundTrip() {
        let app = launchAndBoot()
        app.buttons["PocketRootHost.files"].tap()

        deleteGuestFileIfPresent(
            named: Self.systemImportFixtureName,
            in: app
        )
        guard openFileActionsMenu(in: app) else {
            return
        }
        let importFile = app.buttons["Import File"]
        XCTAssertTrue(importFile.waitForExistence(timeout: 10))
        guard waitForHittable(importFile) else {
            return
        }
        importFile.tap()

        openHostDocuments(in: app)
        let fixture = app.cells[
            "\(Self.systemImportFixtureDisplayName), txt"
        ]
        XCTAssertTrue(fixture.waitForExistence(timeout: 30))
        fixture.tap()

        let imported = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/\(Self.systemImportFixtureName)"
        ]
        XCTAssertTrue(imported.waitForExistence(timeout: 30))
        guard waitForHittable(imported) else {
            return
        }
        flushGuestState(in: app)
        app.buttons["PocketRootHost.files"].tap()
        let reopenedImport = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/\(Self.systemImportFixtureName)"
        ]
        XCTAssertTrue(reopenedImport.waitForExistence(timeout: 30))
        guard waitForHittable(reopenedImport) else {
            return
        }
        reopenedImport.press(forDuration: 1)
        app.buttons["Share / Export"].tap()

        let saveToFiles = app.cells.matching(
            NSPredicate(
                format: "label IN %@",
                ["Save to Files", "存储到“文件”", "存储到文件"]
            )
        ).firstMatch
        XCTAssertTrue(saveToFiles.waitForExistence(timeout: 30))
        saveToFiles.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).tap()

        openHostDocuments(in: app)
        let save = app.buttons.matching(
            NSPredicate(format: "label IN %@", ["Save", "存储"])
        ).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 30))
        save.tap()
        let replace = app.buttons.matching(
            NSPredicate(format: "label IN %@", ["Replace", "替换"])
        ).firstMatch
        if replace.waitForExistence(timeout: 10) {
            replace.tap()
        }
        if dismissShareSheetIfNeeded(in: app) {
            returnToHost(in: app)
        } else {
            // iOS 18.0 can leave the app-hosted ActivityViewController
            // inaccessible after the document picker returns. Restarting the
            // host removes that system-owned UI while preserving the installed
            // RootFS and the files being verified by the remainder of the test.
            relaunchAndBoot(app)
        }
        let filesButton = app.buttons["PocketRootHost.files"]
        XCTAssertTrue(filesButton.waitForExistence(timeout: 10))
        filesButton.tap()

        let persistedImport = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/\(Self.systemImportFixtureName)"
        ]
        XCTAssertTrue(persistedImport.waitForExistence(timeout: 30))
        guard waitForHittable(persistedImport) else {
            return
        }
        persistedImport.press(forDuration: 1)
        app.buttons["Delete"].tap()
        confirmDeletion(of: Self.systemImportFixtureName, in: app)
        wait(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: persistedImport,
            timeout: 30
        )

        guard openFileActionsMenu(in: app) else {
            return
        }
        XCTAssertTrue(importFile.waitForExistence(timeout: 10))
        guard waitForHittable(importFile) else {
            return
        }
        importFile.tap()
        openHostDocuments(in: app)
        let exported = app.cells[
            "\(Self.systemImportFixtureDisplayName), txt"
        ]
        XCTAssertTrue(exported.waitForExistence(timeout: 30))
        exported.tap()

        let reimported = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/\(Self.systemImportFixtureName)"
        ]
        XCTAssertTrue(reimported.waitForExistence(timeout: 30))
        guard waitForHittable(reimported) else {
            return
        }
        reimported.tap()
        let preview = app.staticTexts["PocketRootFiles.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 30))
        XCTAssertEqual(preview.label, Self.systemFixtureContents)
        tapBackButton(in: app)
        deleteGuestFileIfPresent(
            named: Self.systemImportFixtureName,
            in: app
        )
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
            "seq 1 128; printf '__PTY_OUTPUT_128__\\n'; "
                + "printf 'after-foreground\\n' "
                + ">> /root/pocketroot-device-ui-smoke/lifecycle.txt\n"
        )
        wait(
            for: NSPredicate(
                format: "value CONTAINS %@",
                "__PTY_OUTPUT_128__"
            ),
            evaluatedWith: terminal,
            timeout: 30
        )

        let portraitSize = queryTerminalSize(
            terminal,
            marker: "__PORTRAIT_SIZE__"
        )
        XCUIDevice.shared.orientation = .landscapeLeft
        allowTerminalToDrain()
        terminal = terminalElement(in: app)
        XCTAssertTrue(terminal.exists)
        terminal.tap()
        let landscapeSize = queryTerminalSize(
            terminal,
            marker: "__LANDSCAPE_SIZE__"
        )
        XCTAssertGreaterThan(landscapeSize.columns, portraitSize.columns)

        XCUIDevice.shared.orientation = .portrait
        allowTerminalToDrain()
        terminal = terminalElement(in: app)
        XCTAssertTrue(terminal.exists)
        terminal.tap()
        let returnedPortraitSize = queryTerminalSize(
            terminal,
            marker: "__RETURNED_PORTRAIT_SIZE__"
        )
        XCTAssertLessThan(
            returnedPortraitSize.columns,
            landscapeSize.columns
        )

        tapBackButton(in: app)
        XCTAssertTrue(terminalButton.waitForExistence(timeout: 30))
        wait(
            for: NSPredicate(
                format: "enabled == true AND value == %@",
                "Session Closed"
            ),
            evaluatedWith: terminalButton,
            timeout: 30
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

    func testWorkspaceKeepsPTYAliveAcrossFilesTab() {
        let app = launchAndBoot()
        let workspaceButton = app.buttons["PocketRootHost.workspace"]
        XCTAssertTrue(workspaceButton.waitForExistence(timeout: 10))
        workspaceButton.tap()

        var terminal = terminalElement(in: app)
        XCTAssertTrue(terminal.waitForExistence(timeout: 30))
        terminal.tap()
        terminal.typeText(
            "rm -f /root/pocketroot-workspace-smoke.txt; "
                + "printf 'workspace tab persistence\\n' "
                + "> /root/pocketroot-workspace-smoke.txt; "
                + "printf '__WORKSPACE_SESSION_ALIVE__\\n'\n"
        )
        wait(
            for: NSPredicate(
                format: "value CONTAINS %@",
                "__WORKSPACE_SESSION_ALIVE__"
            ),
            evaluatedWith: terminal,
            timeout: 30
        )

        dismissKeyboard(in: app)

        let filesSurface = app.segmentedControls.buttons["Files"]
        XCTAssertTrue(filesSurface.waitForExistence(timeout: 10))
        filesSurface.tap()

        let file = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/pocketroot-workspace-smoke.txt"
        ]
        XCTAssertTrue(file.waitForExistence(timeout: 30))
        file.tap()
        let preview = app.staticTexts["PocketRootFiles.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 30))
        XCTAssertEqual(preview.label, "workspace tab persistence\n")

        let terminalSurface = app.segmentedControls.buttons["Terminal"]
        XCTAssertTrue(terminalSurface.waitForExistence(timeout: 10))
        terminalSurface.tap()
        terminal = terminalElement(in: app)
        XCTAssertTrue(terminal.waitForExistence(timeout: 30))
        wait(
            for: NSPredicate(
                format: "value CONTAINS %@",
                "__WORKSPACE_SESSION_ALIVE__"
            ),
            evaluatedWith: terminal,
            timeout: 10
        )

        tapBackButton(in: app)
        XCTAssertTrue(workspaceButton.waitForExistence(timeout: 30))
        wait(
            for: NSPredicate(
                format: "enabled == true AND value == %@",
                "Session Closed"
            ),
            evaluatedWith: workspaceButton,
            timeout: 30
        )
    }

    func testIntegratedWorkspaceBootsAndOwnsShutdownOrdering() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-PocketRootUITesting"
        ]
        app.launch()

        let hostStatus = app.staticTexts["PocketRootHost.status"]
        XCTAssertTrue(hostStatus.waitForExistence(timeout: 10))
        XCTAssertEqual(hostStatus.label, "Runtime: Ready to Boot")

        let integratedButton =
            app.buttons["PocketRootHost.integratedWorkspace"]
        XCTAssertTrue(integratedButton.waitForExistence(timeout: 10))
        integratedButton.tap()

        let integratedWorkspace = app.descendants(matching: .any)[
            "PocketRootIshWorkspace"
        ]
        XCTAssertTrue(integratedWorkspace.waitForExistence(timeout: 10))

        let terminal = terminalElement(in: app)
        XCTAssertTrue(terminal.waitForExistence(timeout: 90))
        terminal.tap()
        terminal.typeText(
            "rm -f /root/pocketroot-integrated-smoke.txt; "
                + "printf 'integrated workspace\\n' "
                + "> /root/pocketroot-integrated-smoke.txt; "
                + "printf '__INTEGRATED_WORKSPACE_READY__\\n'\n"
        )
        wait(
            for: NSPredicate(
                format: "value CONTAINS %@",
                "__INTEGRATED_WORKSPACE_READY__"
            ),
            evaluatedWith: terminal,
            timeout: 30
        )

        dismissKeyboard(in: app)
        let filesSurface = app.segmentedControls.buttons["Files"]
        XCTAssertTrue(filesSurface.waitForExistence(timeout: 10))
        filesSurface.tap()

        let file = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/pocketroot-integrated-smoke.txt"
        ]
        XCTAssertTrue(file.waitForExistence(timeout: 30))
        file.tap()
        let preview = app.staticTexts["PocketRootFiles.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 30))
        XCTAssertEqual(preview.label, "integrated workspace\n")

        returnToHost(in: app)
        wait(
            for: NSPredicate(format: "label == %@", "Runtime: Ready"),
            evaluatedWith: hostStatus,
            timeout: 30
        )

        let shutdownButton = app.buttons["PocketRootHost.shutdown"]
        XCTAssertTrue(shutdownButton.isEnabled)
        shutdownButton.tap()
        wait(
            for: NSPredicate(
                format: "label == %@",
                "Runtime: Restart App"
            ),
            evaluatedWith: hostStatus,
            timeout: 30
        )
        XCTAssertFalse(integratedButton.isEnabled)
    }

    private func launchAndBoot() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-PocketRootUITesting"
        ]
        app.launch()
        bootRuntime(in: app)
        return app
    }

    private func relaunchAndBoot(_ app: XCUIApplication) {
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        app.launch()
        bootRuntime(in: app)
    }

    private func flushGuestState(in app: XCUIApplication) {
        returnToHost(in: app)
        app.buttons["PocketRootHost.terminal"].tap()

        let terminal = terminalElement(in: app)
        XCTAssertTrue(terminal.waitForExistence(timeout: 30))
        terminal.tap()
        let marker = "__POCKETROOT_SYSTEM_FILE_SYNCED__"
        terminal.typeText("sync && printf '\(marker)\\n'\n")
        wait(
            for: NSPredicate(format: "value CONTAINS %@", marker),
            evaluatedWith: terminal,
            timeout: 30
        )
        dismissKeyboard(in: app)
        returnToHost(in: app)
    }

    private func bootRuntime(in app: XCUIApplication) {
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
    }

    private func terminalElement(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["PocketRootTerminal.pty"]
    }

    private func confirmDeletion(
        of itemName: String,
        in app: XCUIApplication
    ) {
        let alert = app.alerts["Delete Item?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["Delete \(itemName)"].tap()
    }

    private func deleteGuestFileIfPresent(
        named itemName: String,
        in app: XCUIApplication
    ) {
        let file = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/\(itemName)"
        ]
        guard file.waitForExistence(timeout: 3) else {
            return
        }
        guard waitForHittable(file) else {
            return
        }
        file.press(forDuration: 1)
        app.buttons["Delete"].tap()
        confirmDeletion(of: itemName, in: app)
        wait(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: file,
            timeout: 30
        )
    }

    private func openHostDocuments(in app: XCUIApplication) {
        let browse = app.buttons.matching(
            NSPredicate(format: "label IN %@", ["Browse", "浏览"])
        ).firstMatch
        if browse.waitForExistence(timeout: 10) {
            browse.tap()
        }

        let localLocation = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label IN %@",
                [
                    "On My iPhone",
                    "On My iPad",
                    "我的 iPhone",
                    "我的 iPad",
                ]
            )
        ).firstMatch
        XCTAssertTrue(localLocation.waitForExistence(timeout: 30))
        localLocation.tap()

        let hostDocuments = app.cells.matching(
            NSPredicate(
                format: "identifier == %@ OR label BEGINSWITH %@",
                "PocketRoot Host, Container",
                "PocketRoot Host,"
            )
        ).firstMatch
        XCTAssertTrue(hostDocuments.waitForExistence(timeout: 30))
        hostDocuments.tap()
    }

    private func dismissShareSheetIfNeeded(
        in app: XCUIApplication
    ) -> Bool {
        let activityView = app.otherElements["ActivityListView"]
        let hostActions = app.buttons["PocketRootFiles.actions"]
        let hostIsHittable = NSPredicate(format: "hittable == true")

        for attempt in 0..<3 {
            if waitWithoutAssertion(
                for: hostIsHittable,
                evaluatedWith: hostActions,
                timeout: attempt == 0 ? 3 : 2
            ) {
                return true
            }
            if attempt == 0, !activityView.exists {
                _ = activityView.waitForExistence(timeout: 3)
            }
            guard activityView.exists else {
                continue
            }

            let close = app.buttons.matching(
                NSPredicate(format: "label IN %@", ["Close", "关闭"])
            ).firstMatch
            let shareDismissedOrCloseHittable = NSPredicate { _, _ in
                hostActions.isHittable || !activityView.exists
                    || close.isHittable
            }
            _ = waitWithoutAssertion(
                for: shareDismissedOrCloseHittable,
                evaluatedWith: app,
                timeout: 5
            )
            if hostActions.isHittable {
                return true
            }
            guard activityView.exists else {
                continue
            }

            if close.isHittable {
                tapCurrentFrame(of: close, in: app)
            } else {
                // iPad presents the activity view as a popover without a
                // Close button. Tap outside its current frame to dismiss it.
                let tappedOutside = tapOutsideCurrentFrame(
                    of: activityView,
                    in: app
                )
                if !tappedOutside {
                    // A stale or full-screen activity view has no safe gesture
                    // target. Let the caller use the relaunch recovery path.
                    continue
                }
            }
        }

        // System UI can leave a stale ActivityListView accessibility node
        // behind. The host action button becoming hittable is the reliable
        // signal that the share sheet no longer blocks input. If iOS keeps the
        // remote view attached, the caller relaunches the host and continues
        // validating the persisted Linux and exported files.
        return waitWithoutAssertion(
            for: hostIsHittable,
            evaluatedWith: hostActions,
            timeout: 5
        )
    }

    private func tapCurrentFrame(
        of element: XCUIElement,
        in app: XCUIApplication
    ) {
        let appFrame = app.frame
        let elementFrame = element.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(
                CGVector(
                    dx: elementFrame.midX - appFrame.minX,
                    dy: elementFrame.midY - appFrame.minY
                )
            )
            .tap()
    }

    private func tapOutsideCurrentFrame(
        of element: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        let appFrame = app.frame
        let elementFrame = element.frame
        guard appFrame.width > 2, appFrame.height > 2 else {
            return false
        }
        let candidatePoints = [
            CGPoint(x: appFrame.minX + 1, y: appFrame.minY + 1),
            CGPoint(x: appFrame.maxX - 1, y: appFrame.minY + 1),
            CGPoint(x: appFrame.minX + 1, y: appFrame.maxY - 1),
            CGPoint(x: appFrame.maxX - 1, y: appFrame.maxY - 1),
        ]
        guard let point = candidatePoints.first(
            where: { !elementFrame.contains($0) }
        ) else {
            return false
        }
        let offset = CGVector(
            dx: (point.x - appFrame.minX) / appFrame.width,
            dy: (point.y - appFrame.minY) / appFrame.height
        )
        app.coordinate(withNormalizedOffset: offset).tap()
        return true
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

    private func queryTerminalSize(
        _ terminal: XCUIElement,
        marker: String
    ) -> (rows: Int, columns: Int) {
        terminal.typeText("printf '\(marker)'; stty size\n")

        var result: (rows: Int, columns: Int)?
        let expression = try! NSRegularExpression(
            pattern: NSRegularExpression.escapedPattern(for: marker)
                + #"([0-9]+) ([0-9]+)"#
        )
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement,
                  let value = element.value as? String
            else {
                return false
            }
            let range = NSRange(value.startIndex..., in: value)
            guard let match = expression.firstMatch(
                in: value,
                range: range
            ),
                let rowsRange = Range(match.range(at: 1), in: value),
                let columnsRange = Range(match.range(at: 2), in: value),
                let rows = Int(value[rowsRange]),
                let columns = Int(value[columnsRange])
            else {
                return false
            }
            result = (rows, columns)
            return true
        }
        wait(for: predicate, evaluatedWith: terminal, timeout: 30)
        return result ?? (0, 0)
    }

    @discardableResult
    private func wait(
        for predicate: NSPredicate,
        evaluatedWith object: Any,
        timeout: TimeInterval,
        failureDescription: String? = nil,
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
            failureDescription ?? "predicate \(predicate) to become true",
            file: file,
            line: line
        )
        return result == .completed
    }

    private func waitWithoutAssertion(
        for predicate: NSPredicate,
        evaluatedWith object: Any,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: object
        )
        return XCTWaiter.wait(
            for: [expectation],
            timeout: timeout
        ) == .completed
    }

    private func waitForEnabled(
        _ element: XCUIElement,
        timeout: TimeInterval = 30
    ) {
        wait(
            for: NSPredicate(format: "enabled == true"),
            evaluatedWith: element,
            timeout: timeout,
            failureDescription:
                "element \(element.identifier) to become enabled"
        )
    }

    @discardableResult
    private func openFileActionsMenu(
        in app: XCUIApplication
    ) -> Bool {
        // System document and share controllers can finish dismissing after
        // the host Files screen is visible. Re-query the button and wait for
        // a valid activation point before tapping, especially on iPad.
        let actions = app.buttons["PocketRootFiles.actions"]
        guard actions.waitForExistence(timeout: 30) else {
            XCTFail("file actions button to exist")
            return false
        }
        waitForEnabled(actions)
        guard waitForHittable(actions) else {
            return false
        }
        actions.tap()
        return true
    }

    @discardableResult
    private func waitForHittable(
        _ element: XCUIElement,
        timeout: TimeInterval = 30,
        failureDescription: String? = nil
    ) -> Bool {
        wait(
            for: NSPredicate(format: "hittable == true"),
            evaluatedWith: element,
            timeout: timeout,
            failureDescription: failureDescription
                ?? "element \(element.identifier) to become hittable"
        )
    }
}
