import XCTest

@MainActor
final class PocketRootHostAppUITests: XCTestCase {
    private static let systemImportFixtureName =
        "pocketroot-system-file-ui-fixture.txt"
    private static let systemImportFixtureDisplayName =
        "pocketroot-system-file-ui-fixture"
    private static let systemFixtureContents =
        "PocketRoot system file transfer UI fixture\n"

    private func recordCheckpoint(_ name: String) {
        print("PocketRoot Host UI checkpoint: \(name)")
        let attachment = XCTAttachment(string: name)
        attachment.name = "PocketRoot Host UI checkpoint"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFilesCreateAndDelete() {
        let app = launchAndBoot()
        let filesButton = app.buttons["PocketRootHost.files"]
        XCTAssertTrue(filesButton.waitForExistence(timeout: 10))
        waitForEnabled(filesButton)
        XCTAssertTrue(waitForHittable(filesButton))
        filesButton.tap()

        let suffix = String(UUID().uuidString.prefix(8)).lowercased()
        let fileName = "files-\(suffix).txt"
        let renamedFileName = "\(fileName).renamed"
        let folderName = "folder-\(suffix)"
        let nestedFileName = "nested-\(suffix).txt"
        let actions = app.buttons["PocketRootFiles.actions"]
        if !actions.waitForExistence(timeout: 10) {
            XCTAssertTrue(waitForHittable(filesButton))
            filesButton.tap()
        }
        XCTAssertTrue(actions.waitForExistence(timeout: 30))
        waitForEnabled(actions)

        actions.tap()
        XCTAssertTrue(app.buttons["Import File"].waitForExistence(timeout: 10))
        app.buttons["New File"].tap()
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.typeText(fileName)
        let file = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/\(fileName)"
        ]
        guard submitCreation(expectedEntry: file, in: app) else {
            return
        }
        waitForEnabled(file)
        guard let rename = openFileEntryContextMenu(
            for: file,
            expectedAction: "Rename",
            in: app
        ) else {
            return
        }
        rename.tap()
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
        dismissKeyboardOnboardingIfPresent(in: app)
        renameAlert.buttons["Rename"].tap()

        let renamedFile = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/\(renamedFileName)"
        ]
        guard renamedFile.waitForExistence(timeout: 30) else {
            XCTFail("renamed file to appear after submitting the rename")
            return
        }
        wait(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: file,
            timeout: 30
        )
        waitForEnabled(renamedFile)
        guard let delete = openFileEntryContextMenu(
            for: renamedFile,
            expectedAction: "Delete",
            in: app
        ) else {
            return
        }
        delete.tap()
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
        let folder = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/\(folderName)"
        ]
        guard submitCreation(expectedEntry: folder, in: app) else {
            return
        }
        let disclosure = app.buttons[
            "PocketRootFiles.disclosure./root/\(folderName)"
        ]
        guard disclosure.waitForExistence(timeout: 10) else {
            XCTFail("new folder disclosure to appear")
            return
        }
        waitForEnabled(disclosure)
        disclosure.tap()
        guard revealFileEntry(folder, in: app) else {
            shutdownRuntime(in: app)
            return
        }
        folder.tap()

        waitForEnabled(actions)
        actions.tap()
        app.buttons["New File"].tap()
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.typeText(nestedFileName)
        let nestedFile = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/\(folderName)/\(nestedFileName)"
        ]
        guard submitCreation(expectedEntry: nestedFile, in: app) else {
            return
        }
        waitForEnabled(actions)
        let childNavigationBar = app.navigationBars[folderName]
        guard childNavigationBar.waitForExistence(timeout: 30) else {
            XCTFail("child folder navigation bar to exist")
            shutdownRuntime(in: app)
            return
        }
        let backButton = childNavigationBar.buttons.element(boundBy: 0)
        XCTAssertTrue(waitForHittable(backButton))
        backButton.tap()

        guard let delete = openFileEntryContextMenu(
            for: folder,
            expectedAction: "Delete",
            in: app
        ) else {
            return
        }
        delete.tap()
        confirmDeletion(of: folderName, in: app)
        wait(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: folder,
            timeout: 30
        )
        shutdownRuntime(in: app)
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
        shutdownRuntime(in: app)
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

        guard openHostDocuments(in: app) else {
            return
        }
        guard importHostFixture(in: app) else {
            return
        }

        let imported = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/\(Self.systemImportFixtureName)"
        ]
        guard revealFileEntry(imported, in: app) else {
            return
        }
        flushGuestState(in: app)
        app.buttons["PocketRootHost.files"].tap()
        let reopenedImport = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/\(Self.systemImportFixtureName)"
        ]
        XCTAssertTrue(reopenedImport.waitForExistence(timeout: 30))
        guard revealFileEntry(reopenedImport, in: app) else {
            return
        }
        guard let share = openFileEntryContextMenu(
            for: reopenedImport,
            expectedAction: "Share / Export",
            in: app
        ) else {
            return
        }
        share.tap()

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

        guard openHostDocuments(in: app) else {
            return
        }
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
        guard revealFileEntry(persistedImport, in: app) else {
            return
        }
        guard let delete = openFileEntryContextMenu(
            for: persistedImport,
            expectedAction: "Delete",
            in: app
        ) else {
            return
        }
        delete.tap()
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
        guard openHostDocuments(in: app) else {
            return
        }
        guard importHostFixture(in: app) else {
            return
        }

        let reimported = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/\(Self.systemImportFixtureName)"
        ]
        guard revealFileEntry(reimported, in: app) else {
            return
        }
        tapCurrentFrame(of: reimported, in: app)
        let preview = app.staticTexts["PocketRootFiles.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 30))
        XCTAssertEqual(preview.label, Self.systemFixtureContents)
        tapBackButton(in: app)
        deleteGuestFileIfPresent(
            named: Self.systemImportFixtureName,
            in: app
        )
        shutdownRuntime(in: app)
    }

    func testPTYLifecycleAndShutdown() {
        let device = XCUIDevice.shared
        device.orientation = .portrait
        addTeardownBlock {
            if device.orientation != .portrait {
                device.orientation = .portrait
            }
        }

        let app = launchAndBoot()
        recordCheckpoint("runtime-booted")
        let terminalButton = app.buttons["PocketRootHost.terminal"]
        terminalButton.tap()

        var terminal = terminalElement(in: app)
        XCTAssertTrue(terminal.waitForExistence(timeout: 30))
        dismissWirelessDataPermissionIfPresent(blocking: terminal)
        terminal.tap()
        let setupMarker = "__PTY_LIFECYCLE_SETUP_READY__"
        let setupCommand =
            "rm -rf /root/pocketroot-device-ui-smoke; "
                + "mkdir -p /root/pocketroot-device-ui-smoke; "
                + "printf 'before-background\\n' "
                + "> /root/pocketroot-device-ui-smoke/lifecycle.txt; "
                + "printf '__PTY_LIFECYCLE_SETUP_'; "
                + "printf 'READY__\\n'\n"
        terminal.typeText(setupCommand)
        if !waitWithoutAssertion(
            for: NSPredicate(
                format: "value CONTAINS %@",
                setupMarker
            ),
            evaluatedWith: terminal,
            timeout: 15
        ) {
            terminal.tap()
            terminal.typeText(setupCommand)
        }
        guard wait(
            for: NSPredicate(
                format: "value CONTAINS %@",
                setupMarker
            ),
            evaluatedWith: terminal,
            timeout: 30
        ) else {
            return
        }

        let interactiveStartedMarker = "__INTERACTIVE_TOP_STARTED__"
        let interactiveInterruptedMarker = "__INTERACTIVE_TOP_INTERRUPTED__"
        terminal.tap()
        terminal.typeText(
            "printf '\(interactiveStartedMarker)\\n'; "
                + "top; printf '\(interactiveInterruptedMarker)\\n'\n"
        )
        guard wait(
            for: NSPredicate(
                format: "value CONTAINS %@",
                interactiveStartedMarker
            ),
            evaluatedWith: terminal,
            timeout: 30
        ) else {
            return
        }
        guard wait(
            for: NSPredicate(format: "value CONTAINS %@", "Mem:"),
            evaluatedWith: terminal,
            timeout: 30
        ) else {
            return
        }
        recordCheckpoint("interactive-top-output-observed")
        dismissKeyboardOnboardingIfPresent(in: app)
        let interruptButton = app.buttons["PocketRootTerminal.key.ctrl-c"]
        guard let interruptFrames = waitForInteractionFrames(
            of: interruptButton,
            in: app,
            timeout: 10
        ) else {
            XCTFail("Ctrl-C to expose a usable interaction frame")
            return
        }
        // Fresh iOS 18.0 simulators can present keyboard onboarding over the
        // accessory bar. After dismissing it above, avoid XCTest's redundant
        // kAXScrollToVisibleAction and tap the verified frame through the app
        // coordinate. The marker assertion below still proves Ctrl-C delivery.
        tapFrame(
            interruptFrames.elementFrame,
            in: interruptFrames.appFrame,
            using: app
        )
        guard wait(
            for: NSPredicate(
                format: "value CONTAINS %@",
                interactiveInterruptedMarker
            ),
            evaluatedWith: terminal,
            timeout: 30
        ) else {
            return
        }
        recordCheckpoint("interactive-top-interrupted")

        device.press(.home)
        let springboard = XCUIApplication(
            bundleIdentifier: "com.apple.springboard"
        )
        guard springboard.wait(for: .runningForeground, timeout: 15) else {
            XCTFail("The system UI did not replace the Host App foreground.")
            return
        }
        recordCheckpoint("background-transition-observed")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        terminal = terminalElement(in: app)
        XCTAssertTrue(terminal.waitForExistence(timeout: 30))
        recordCheckpoint("foreground-restored")
        guard wait(
            for: NSPredicate(
                format: "value CONTAINS %@",
                setupMarker
            ),
            evaluatedWith: terminal,
            timeout: 30
        ) else {
            return
        }
        recordCheckpoint("pty-session-preserved-after-foreground")
        terminal.tap()
        terminal.typeText(
            "seq 1 128; printf '__PTY_OUTPUT_128__\\n'; "
                + "printf 'after-foreground\\n' "
                + ">> /root/pocketroot-device-ui-smoke/lifecycle.txt\n"
        )
        guard wait(
            for: NSPredicate(
                format: "value CONTAINS %@",
                "__PTY_OUTPUT_128__"
            ),
            evaluatedWith: terminal,
            timeout: 30
        ) else {
            return
        }
        recordCheckpoint("sustained-output-observed")

        let portraitSize = queryTerminalSize(
            terminal,
            marker: "__PORTRAIT_SIZE__"
        )
        let portraitWindowFrame = app.windows.firstMatch.frame
        device.orientation = .landscapeLeft
        allowTerminalToDrain()
        terminal = terminalElement(in: app)
        XCTAssertTrue(terminal.exists)
        let windowDidRotate = waitForWindowWidthChange(
            in: app,
            from: portraitWindowFrame.width,
            direction: .increasing,
            timeout: 15
        )
        guard windowDidRotate else {
            device.orientation = .portrait
            XCTFail("The Host App window did not rotate to landscape geometry.")
            return
        }
        terminal.tap()
        let landscapeSize = queryTerminalSize(
            terminal,
            marker: "__LANDSCAPE_SIZE__"
        )
        XCTAssertGreaterThan(landscapeSize.columns, portraitSize.columns)
        recordCheckpoint("landscape-resize-verified")

        let landscapeWindowFrame = app.windows.firstMatch.frame
        device.orientation = .portrait
        XCTAssertTrue(
            waitForWindowWidthChange(
                in: app,
                from: landscapeWindowFrame.width,
                direction: .decreasing,
                timeout: 15
            ),
            "The Host App window did not return to portrait geometry."
        )
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
        recordCheckpoint("portrait-resize-verified")

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
        recordCheckpoint("first-session-closed")

        terminalButton.tap()
        terminal = terminalElement(in: app)
        XCTAssertTrue(terminal.waitForExistence(timeout: 30))
        terminal.tap()
        let reopenCommand =
            "grep -qx 'after-reopen' "
                + "/root/pocketroot-device-ui-smoke/lifecycle.txt "
                + "|| printf 'after-reopen\\n' "
                + ">> /root/pocketroot-device-ui-smoke/lifecycle.txt; "
                + "exit 0\n"
        terminal.typeText(reopenCommand)

        let exitedNavigationBar = app.navigationBars["Terminal Exited (0)"]
        if !exitedNavigationBar.waitForExistence(timeout: 15) {
            terminal.tap()
            terminal.typeText(reopenCommand)
        }
        XCTAssertTrue(exitedNavigationBar.waitForExistence(timeout: 30))
        let endedInterruptButton = app.buttons[
            "PocketRootTerminal.key.ctrl-c"
        ]
        XCTAssertTrue(endedInterruptButton.waitForExistence(timeout: 10))
        wait(
            for: NSPredicate(format: "enabled == false"),
            evaluatedWith: endedInterruptButton,
            timeout: 10
        )
        recordCheckpoint("reopened-session-exited")
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
        recordCheckpoint("guest-file-preview-verified")

        shutdownRuntime(in: app)
        let shutdownButton = app.buttons["PocketRootHost.shutdown"]
        XCTAssertFalse(terminalButton.isEnabled)
        XCTAssertFalse(filesButton.isEnabled)
        XCTAssertFalse(shutdownButton.isEnabled)
        recordCheckpoint("runtime-shutdown-verified")
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
        shutdownRuntime(in: app)
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
        let integratedRunID = UUID().uuidString.lowercased()
        let integratedMarker =
            "__INTEGRATED_WORKSPACE_READY_\(integratedRunID)__"
        let integratedContents =
            "integrated workspace \(integratedRunID)\n"
        terminal.typeText(
            "rm -f /root/pocketroot-integrated-smoke.txt; "
                + "printf 'integrated workspace \(integratedRunID)\\n' "
                + "> /root/pocketroot-integrated-smoke.txt; "
                + "printf '\(integratedMarker)\\n'\n"
        )
        // SwiftTerm's accessibility value can lag behind output that the
        // guest has already produced. Give it one bounded observation window,
        // then let the stronger Files entry and exact preview assertions below
        // prove that the command completed instead of recording a false
        // terminal-text failure.
        _ = waitWithoutAssertion(
            for: NSPredicate(
                format: "value CONTAINS %@",
                integratedMarker
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
        XCTAssertEqual(preview.label, integratedContents)

        returnToHost(in: app)
        wait(
            for: NSPredicate(format: "label == %@", "Runtime: Ready"),
            evaluatedWith: hostStatus,
            timeout: 30
        )

        shutdownRuntime(in: app)
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
        waitForEnabled(bootButton, timeout: 10)
        XCTAssertTrue(waitForHittable(bootButton))
        bootButton.tap()
        let runtimeReady = NSPredicate(
            format: "label == %@",
            "Runtime: Ready"
        )
        let bootStarted = NSPredicate(
            format: "label != %@",
            "Runtime: Ready to Boot"
        )
        if !waitWithoutAssertion(
            for: bootStarted,
            evaluatedWith: status,
            timeout: 5
        ) {
            XCTAssertTrue(waitForHittable(bootButton))
            bootButton.tap()
        }
        wait(
            for: runtimeReady,
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

    private func dismissWirelessDataPermissionIfPresent(
        blocking terminal: XCUIElement
    ) {
        let springboard = XCUIApplication(
            bundleIdentifier: "com.apple.springboard"
        )
        if tapWirelessDataDenyButton(in: springboard) {
            recordCheckpoint("wireless-data-permission-denied")
            return
        }

        let environment = ProcessInfo.processInfo.environment
        guard environment["SIMULATOR_UDID"] == nil else {
            return
        }
        let alertDeadline = Date().addingTimeInterval(5)
        while Date() < alertDeadline {
            if tapWirelessDataDenyButton(in: springboard) {
                recordCheckpoint("wireless-data-permission-denied")
                return
            }
            RunLoop.current.run(
                until: Date().addingTimeInterval(0.2)
            )
        }
        guard terminal.isHittable else {
            XCTFail("An unexpected system alert blocked terminal input.")
            return
        }
    }

    private func tapWirelessDataDenyButton(
        in springboard: XCUIApplication
    ) -> Bool {
        for label in ["Don’t Allow", "Don't Allow", "不允许"] {
            let button = springboard.buttons[label]
            if button.exists {
                button.tap()
                _ = button.waitForNonExistence(timeout: 5)
                RunLoop.current.run(
                    until: Date().addingTimeInterval(0.5)
                )
                return true
            }
        }

        // SpringBoard does not inherit the Host App's test language. For an
        // otherwise-localized wireless-data prompt, require the alert to name
        // this app and to expose the three expected choices before selecting
        // the final (deny) action by position. This avoids dismissing an
        // unrelated system alert or choosing an affirmative two-button action.
        let alert = springboard.alerts.firstMatch
        guard alert.exists else {
            return false
        }
        let hostAppReference = alert.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "PocketRoot Host")
        ).firstMatch
        let buttons = alert.buttons
        guard hostAppReference.exists, buttons.count == 3 else {
            return false
        }
        let denialButton = buttons.element(boundBy: 2)
        guard denialButton.exists, denialButton.isHittable else {
            return false
        }
        denialButton.tap()
        guard alert.waitForNonExistence(timeout: 5) else {
            return false
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        return true
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
        guard revealFileEntry(file, in: app) else {
            return
        }
        guard let delete = openFileEntryContextMenu(
            for: file,
            expectedAction: "Delete",
            in: app
        ) else {
            return
        }
        delete.tap()
        confirmDeletion(of: itemName, in: app)
        wait(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: file,
            timeout: 30
        )
    }

    private func openHostDocuments(in app: XCUIApplication) -> Bool {
        let browse = app.buttons.matching(
            NSPredicate(format: "label IN %@", ["Browse", "浏览"])
        ).firstMatch

        // The iOS document picker preserves its last visited directory. On a
        // later import or export in this test it can reopen directly inside
        // the host container instead of showing either the local location or
        // the container cell again.
        let pickerNavigationBar = app.navigationBars[
            "FullDocumentManagerViewControllerNavigationBar"
        ]
        let hostDocumentLabels = [
            "PocketRoot Host, Actions Menu",
            "PocketRoot Host, 操作菜单",
            "PocketRoot Host，操作菜单",
        ]
        let currentHostDocuments = pickerNavigationBar.buttons.matching(
            NSPredicate(
                format: "label IN %@",
                hostDocumentLabels
            )
        ).firstMatch
        let localLocationLabels = [
            "On My iPhone",
            "On My iPad",
            "我的 iPhone",
            "我的 iPad",
        ]
        let localLocationPredicate = NSPredicate(
            format: "identifier IN %@ OR label IN %@",
            [
                "DOC.sidebar.item.On My iPhone",
                "DOC.sidebar.item.On My iPad",
            ],
            localLocationLabels
        )
        let sidebarLocalLocation = app.cells.matching(
            localLocationPredicate
        ).firstMatch
        let fallbackLocalLocation = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label IN %@",
                localLocationLabels
            )
        ).firstMatch
        let hostFixture = app.cells[
            "\(Self.systemImportFixtureDisplayName), txt"
        ]
        // The minimum Xcode 16 runner can present the document manager on
        // Recents before its Browse tab enters the accessibility tree, while a
        // restored Host location can also expose its navigation bar before its
        // file list. Spend one deadline waiting for either the fixture itself,
        // a local location, or a usable Browse transition.
        let pickerDeadline = Date().addingTimeInterval(60)
        var localLocation: XCUIElement?
        var didTapBrowse = false
        while Date() < pickerDeadline {
            if currentHostDocuments.exists {
                if hostFixture.exists {
                    return true
                }
                // An iPad sidebar can keep the local location visible while
                // the restored Host file list is still loading. Once the Host
                // navigation state is present, stay there instead of letting
                // the sidebar take us back out of the destination.
                RunLoop.current.run(
                    until: Date().addingTimeInterval(0.2)
                )
                continue
            }
            if sidebarLocalLocation.exists {
                localLocation = sidebarLocalLocation
                break
            }
            if fallbackLocalLocation.exists {
                localLocation = fallbackLocalLocation
                break
            }
            if !didTapBrowse, browse.exists {
                guard let frames = waitForInteractionFrames(
                    of: browse,
                    in: app,
                    timeout: 10
                ) else {
                    XCTFail("document picker Browse to become hittable")
                    return false
                }
                tapFrame(
                    frames.elementFrame,
                    in: frames.appFrame,
                    using: app
                )
                didTapBrowse = true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        if currentHostDocuments.exists {
            guard hostFixture.waitForExistence(timeout: 30) else {
                XCTFail("Host Documents fixture to become visible")
                return false
            }
            return true
        }
        guard let localLocation else {
            XCTFail("document picker to expose a usable Host or local destination")
            return false
        }

        let hostDocuments = app.cells.matching(
            NSPredicate(
                format: "identifier == %@ OR label BEGINSWITH %@",
                "PocketRoot Host, Container",
                "PocketRoot Host,"
            )
        ).firstMatch
        let hostDestination = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ OR label IN %@ OR label BEGINSWITH %@",
                "PocketRoot Host, Container",
                hostDocumentLabels,
                "PocketRoot Host,"
            )
        ).firstMatch
        var openedHostDestination = false
        for _ in 0..<2 {
            // Browse can restore the last Host destination while the local
            // location query is transitioning out of the accessibility tree.
            // Re-check that stronger navigation state before touching a stale
            // local-location element.
            if currentHostDocuments.exists {
                openedHostDestination = true
                break
            }
            guard let frames = waitForInteractionFrames(
                of: localLocation,
                in: app,
                timeout: 5
            ) else {
                if currentHostDocuments.waitForExistence(timeout: 5) {
                    openedHostDestination = true
                    break
                }
                continue
            }
            tapFrame(
                frames.elementFrame,
                in: frames.appFrame,
                using: app
            )
            if hostDestination.waitForExistence(timeout: 10) {
                openedHostDestination = true
                break
            }
        }
        XCTAssertTrue(
            openedHostDestination,
            "local document location to reveal the host container"
        )
        guard openedHostDestination else {
            return false
        }
        if !currentHostDocuments.exists {
            XCTAssertTrue(hostDocuments.exists)
            guard hostDocuments.exists else {
                return false
            }
            hostDocuments.tap()
        }
        guard hostFixture.waitForExistence(timeout: 30) else {
            XCTFail("Host Documents fixture to become visible")
            return false
        }
        return true
    }

    private func importHostFixture(in app: XCUIApplication) -> Bool {
        let fixture = app.cells[
            "\(Self.systemImportFixtureDisplayName), txt"
        ]
        let imported = app.descendants(matching: .any)[
            "PocketRootFiles.entry./root/\(Self.systemImportFixtureName)"
        ]

        // Xcode 16 can synthesize a successful tap while the iOS 18.0
        // document picker keeps the file cell open and never completes the
        // selection. Re-query the current frame and retry once only while the
        // guest file is still absent.
        for _ in 0..<2 {
            guard let frames = waitForInteractionFrames(
                of: fixture,
                in: app,
                timeout: 10
            ) else {
                XCTFail("Host Documents fixture to expose an interaction frame")
                return false
            }
            tapFrame(
                frames.elementFrame,
                in: frames.appFrame,
                using: app
            )
            if imported.waitForExistence(timeout: 15) {
                return true
            }
        }

        XCTFail("Host Documents fixture selection to import the guest file")
        return false
    }

    private func dismissShareSheetIfNeeded(
        in app: XCUIApplication
    ) -> Bool {
        let activityView = app
            .descendants(matching: .any)
            .matching(identifier: "ActivityListView")
            .firstMatch
        let hostActions = app.buttons["PocketRootFiles.actions"]
        if !activityView.waitForExistence(timeout: 3) {
            // Without observing the system sheet, underlying host geometry is
            // not proof that the host owns input. Use the caller's clean
            // relaunch recovery path instead.
            return false
        }

        for _ in 0..<3 {
            guard activityView.exists else {
                return waitForInteractionFrames(
                    of: hostActions,
                    in: app,
                    timeout: 3
                ) != nil
            }

            let close = app.buttons.matching(
                NSPredicate(format: "label IN %@", ["Close", "关闭"])
            ).firstMatch
            if let frames = waitForInteractionFrames(
                of: close,
                in: app,
                timeout: 3
            ) {
                tapFrame(
                    frames.elementFrame,
                    in: frames.appFrame,
                    using: app
                )
            } else {
                // iPad presents the activity view as a popover without a
                // Close button. Snapshot its frame once so disappearance is a
                // recoverable query error, then tap a verified outside point.
                guard let activitySnapshot = try? activityView.snapshot() else {
                    continue
                }
                let tappedOutside = tapOutsideSnapshotFrame(
                    activitySnapshot.frame,
                    in: app
                )
                if !tappedOutside {
                    // A stale or full-screen activity view has no safe gesture
                    // target. Let the caller use the relaunch recovery path.
                    continue
                }
            }

            let activityDismissed = NSPredicate(format: "exists == false")
            if waitWithoutAssertion(
                for: activityDismissed,
                evaluatedWith: activityView,
                timeout: 5
            ) {
                return waitForInteractionFrames(
                    of: hostActions,
                    in: app,
                    timeout: 3
                ) != nil
            }
        }

        // System UI can leave a stale ActivityListView accessibility node
        // behind. Avoid asking another host element for hittability while the
        // accessibility tree is transitional; the caller relaunches the host
        // and continues validating the persisted Linux and exported files.
        return !activityView.exists
            && waitForInteractionFrames(
                of: hostActions,
                in: app,
                timeout: 3
            ) != nil
    }

    private func tapCurrentFrame(
        of element: XCUIElement,
        in app: XCUIApplication
    ) {
        let appFrame = app.frame
        let elementFrame = element.frame
        tapFrame(elementFrame, in: appFrame, using: app)
    }

    private func tapFrame(
        _ elementFrame: CGRect,
        in appFrame: CGRect,
        using app: XCUIApplication
    ) {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(
                CGVector(
                    dx: elementFrame.midX - appFrame.minX,
                    dy: elementFrame.midY - appFrame.minY
                )
            )
            .tap()
    }

    private func waitForInteractionFrames(
        of element: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> (appFrame: CGRect, elementFrame: CGRect)? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.isEnabled {
                let appFrame = app.frame
                let elementFrame = element.frame
                let elementCenter = CGPoint(
                    x: elementFrame.midX,
                    y: elementFrame.midY
                )
                if hasUsableFrame(appFrame),
                   hasUsableFrame(elementFrame),
                   appFrame.contains(elementCenter)
                {
                    return (appFrame, elementFrame)
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return nil
    }

    private func openFileEntryContextMenu(
        for element: XCUIElement,
        expectedAction: String,
        in app: XCUIApplication
    ) -> XCUIElement? {
        let action = app.buttons[expectedAction]
        var lastAppFrame = CGRect.null
        var lastElementFrame = CGRect.null

        for _ in 0..<2 {
            guard let frames = waitForInteractionFrames(
                of: element,
                in: app,
                timeout: 10
            ) else {
                continue
            }
            lastAppFrame = frames.appFrame
            lastElementFrame = frames.elementFrame
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(
                    CGVector(
                        dx: frames.elementFrame.midX - frames.appFrame.minX,
                        dy: frames.elementFrame.midY - frames.appFrame.minY
                    )
                )
                .press(forDuration: 1)
            if action.waitForExistence(timeout: 10) {
                return action
            }
        }

        XCTFail(
            "\(expectedAction) context action to appear; "
                + "app=\(lastAppFrame), element=\(lastElementFrame)"
        )
        return nil
    }

    private func submitCreation(
        expectedEntry: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        dismissKeyboardOnboardingIfPresent(in: app)
        let create = app.buttons["Create"]

        for _ in 0..<2 {
            guard let frames = waitForInteractionFrames(
                of: create,
                in: app,
                timeout: 10
            ) else {
                break
            }
            tapFrame(
                frames.elementFrame,
                in: frames.appFrame,
                using: app
            )
            // File-browser mutations allow up to 30 seconds. Preserve that
            // contract, plus a small accessibility refresh allowance, before
            // deciding whether the captured tap needs its one bounded retry.
            if expectedEntry.waitForExistence(timeout: 35) {
                return true
            }
        }

        XCTFail(
            "created entry to appear after a bounded Create retry"
        )
        return false
    }

    private func tapOutsideSnapshotFrame(
        _ elementFrame: CGRect,
        in app: XCUIApplication
    ) -> Bool {
        let appFrame = app.frame
        guard hasUsableFrame(appFrame),
              hasUsableFrame(elementFrame)
        else {
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

    private func shutdownRuntime(in app: XCUIApplication) {
        returnToHost(in: app)
        let shutdownButton = app.buttons["PocketRootHost.shutdown"]
        XCTAssertTrue(shutdownButton.waitForExistence(timeout: 30))
        waitForEnabled(shutdownButton)
        shutdownButton.tap()

        let status = app.staticTexts["PocketRootHost.status"]
        wait(
            for: NSPredicate(format: "label == %@", "Runtime: Restart App"),
            evaluatedWith: status,
            timeout: 30
        )
    }

    private func allowTerminalToDrain() {
        RunLoop.current.run(until: Date().addingTimeInterval(1))
    }

    private func dismissKeyboardOnboardingIfPresent(
        in app: XCUIApplication
    ) {
        let continueButton = app.buttons["Continue"]
        for _ in 0..<3 {
            guard continueButton.waitForExistence(timeout: 1) else {
                return
            }
            continueButton.tap()
            RunLoop.current.run(
                until: Date().addingTimeInterval(0.5)
            )
        }
        XCTAssertFalse(
            continueButton.exists,
            "The system keyboard onboarding still covers the accessory bar."
        )
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        let keyboard = app.keyboards.element
        for _ in 0..<3 where keyboard.exists {
            let continueButton = app.buttons["Continue"]
            if continueButton.exists {
                continueButton.tap()
            } else {
                let hideKeyboardButton = app.buttons[
                    "PocketRootTerminal.key.dismiss-keyboard"
                ]
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
        let command = "printf '\(marker)'; stty size\n"
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
        terminal.typeText(command)
        if !waitWithoutAssertion(
            for: predicate,
            evaluatedWith: terminal,
            timeout: 15
        ) {
            terminal.tap()
            terminal.typeText(command)
        }
        guard wait(
            for: predicate,
            evaluatedWith: terminal,
            timeout: 30
        ) else {
            return (0, 0)
        }
        return result ?? (0, 0)
    }

    private enum WidthChangeDirection {
        case increasing
        case decreasing
    }

    private func waitForWindowWidthChange(
        in app: XCUIApplication,
        from initialWidth: CGFloat,
        direction: WidthChangeDirection,
        timeout: TimeInterval
    ) -> Bool {
        let window = app.windows.firstMatch
        return waitWithoutAssertion(
            for: NSPredicate { object, _ in
                guard let element = object as? XCUIElement,
                      element.exists
                else {
                    return false
                }
                switch direction {
                case .increasing:
                    return element.frame.width > initialWidth
                case .decreasing:
                    return element.frame.width < initialWidth
                }
            },
            evaluatedWith: window,
            timeout: timeout
        )
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
    private func revealFileEntry(
        _ element: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval = 30
    ) -> Bool {
        let list = app.descendants(matching: .any)[
            "PocketRootFiles.list"
        ]
        guard list.waitForExistence(timeout: 10) else {
            XCTFail("file list to exist")
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let appFrame = app.frame
            let listFrame = list.frame
            let visibleFrame = appFrame.intersection(listFrame)
            let elementFrame = element.frame
            let hasVisibleCenter =
                hasUsableFrame(elementFrame)
                    && hasUsableFrame(visibleFrame)
                    && visibleFrame.contains(
                        CGPoint(x: elementFrame.midX, y: elementFrame.midY)
                    )
            if hasVisibleCenter {
                if element.isEnabled {
                    return true
                }
                RunLoop.current.run(
                    until: Date().addingTimeInterval(0.2)
                )
                continue
            }

            if hasUsableFrame(elementFrame),
               hasUsableFrame(visibleFrame),
               elementFrame.midY < visibleFrame.minY
            {
                list.swipeDown()
            } else {
                list.swipeUp()
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        XCTFail(
            "file entry \(element.identifier) to have a visible interaction frame"
        )
        return false
    }

    private func hasUsableFrame(_ frame: CGRect) -> Bool {
        !frame.isNull
            && !frame.isInfinite
            && frame.minX.isFinite
            && frame.minY.isFinite
            && frame.maxX.isFinite
            && frame.maxY.isFinite
            && frame.width > 1
            && frame.height > 1
    }

    @discardableResult
    private func openFileActionsMenu(
        in app: XCUIApplication
    ) -> Bool {
        // XCTest can briefly expose the SwiftUI navigation bar with infinite,
        // zero-sized frames while system document or share controllers finish
        // dismissing. Asking isHittable in that state records an XCTest
        // failure before a predicate waiter can retry. Re-query the button,
        // validate the captured frames, and tap the verified center through
        // an application coordinate instead.
        var lastAppFrame = CGRect.null
        var lastActionsFrame = CGRect.null

        for attempt in 0..<2 {
            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline {
                let actions = app.buttons["PocketRootFiles.actions"]
                let importFile = app.buttons["Import File"]
                if actions.exists, actions.isEnabled {
                    let appFrame = app.frame
                    let actionsFrame = actions.frame
                    lastAppFrame = appFrame
                    lastActionsFrame = actionsFrame
                    let actionsCenter = CGPoint(
                        x: actionsFrame.midX,
                        y: actionsFrame.midY
                    )

                    if hasUsableFrame(appFrame),
                       hasUsableFrame(actionsFrame),
                       appFrame.contains(actionsCenter)
                    {
                        tapFrame(actionsFrame, in: appFrame, using: app)
                        if importFile.waitForExistence(timeout: 10) {
                            return true
                        }
                        // The captured frame can become stale before the tap.
                        // Do not tap again on a possibly open menu. A relaunch
                        // removes all transitional system UI before one clean
                        // retry, while preserving the installed RootFS/files.
                        break
                    }
                }

                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }

            if attempt == 0 {
                relaunchAndBoot(app)
                let filesButton = app.buttons["PocketRootHost.files"]
                guard filesButton.waitForExistence(timeout: 10) else {
                    XCTFail("Files entry to exist after menu retry relaunch")
                    return false
                }
                filesButton.tap()
            }
        }

        XCTFail(
            "file actions menu to open after a clean retry; "
                + "app=\(lastAppFrame), actions=\(lastActionsFrame)"
        )
        return false
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
