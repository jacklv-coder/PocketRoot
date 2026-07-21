import XCTest
@testable import PocketRootTerminal

final class PocketRootTerminalTests: XCTestCase {
    func testDefaultConfigurationDescribesPendingIntegration() {
        let configuration = PocketRootTerminalConfiguration()

        XCTAssertEqual(configuration.placeholderText, "Terminal integration pending")
        XCTAssertEqual(configuration.prompt, "$ ")
        XCTAssertFalse(configuration.allowsInput)
        XCTAssertTrue(configuration.showsAccessoryView)
    }

    func testCustomConfigurationPreservesValues() {
        let configuration = PocketRootTerminalConfiguration(
            placeholderText: "Waiting for runtime",
            prompt: "root# ",
            allowsInput: true,
            showsAccessoryView: false
        )

        XCTAssertEqual(configuration.placeholderText, "Waiting for runtime")
        XCTAssertEqual(configuration.prompt, "root# ")
        XCTAssertTrue(configuration.allowsInput)
        XCTAssertFalse(configuration.showsAccessoryView)
    }

    func testThemePresetsHaveStablePalettes() {
        XCTAssertEqual(PocketRootTerminalTheme.system.palette, .system)
        XCTAssertEqual(PocketRootTerminalTheme.dark.palette, .dark)
        XCTAssertEqual(PocketRootTerminalTheme.system.fontSize, 14)
    }

    func testControllerMaintainsTranscriptWithoutLoadingUI() async {
        let transcript = await MainActor.run {
            let controller = PocketRootTerminalViewController()
            controller.appendOutput("hello")
            return controller.transcript
        }

        XCTAssertEqual(transcript, "Terminal integration pending\nhello")
    }

    func testControllerCanClearTranscript() async {
        let transcript = await MainActor.run {
            let controller = PocketRootTerminalViewController()
            controller.clearOutput()
            return controller.transcript
        }

        XCTAssertTrue(transcript.isEmpty)
    }
}
