import Foundation
import PocketRootCore

/// Configuration for PocketRoot's terminal surface.
public struct PocketRootTerminalConfiguration: Sendable, Equatable {
    public let placeholderText: String
    public let prompt: String
    public let allowsInput: Bool
    public let showsAccessoryView: Bool
    public let initialWorkingDirectory: String
    public let commandTimeout: Duration
    public let maximumTranscriptCharacters: Int

    public init(
        placeholderText: String = "Terminal integration pending",
        prompt: String = "$ ",
        allowsInput: Bool = false,
        showsAccessoryView: Bool = true,
        initialWorkingDirectory: String = "/root",
        commandTimeout: Duration = .seconds(30),
        maximumTranscriptCharacters: Int = 1_048_576
    ) {
        self.placeholderText = placeholderText
        self.prompt = prompt
        self.allowsInput = allowsInput
        self.showsAccessoryView = showsAccessoryView
        self.initialWorkingDirectory = initialWorkingDirectory
        self.commandTimeout = commandTimeout
        self.maximumTranscriptCharacters = max(1, maximumTranscriptCharacters)
    }

    /// The minimum stateful command-line experience backed by one-shot shell
    /// execution. This does not claim PTY or full-screen interactive support.
    public static func commandLine(
        initialWorkingDirectory: String = "/root",
        commandTimeout: Duration = .seconds(30)
    ) -> PocketRootTerminalConfiguration {
        PocketRootTerminalConfiguration(
            placeholderText: "PocketRoot command terminal ready",
            prompt: "$ ",
            allowsInput: true,
            showsAccessoryView: true,
            initialWorkingDirectory: initialWorkingDirectory,
            commandTimeout: commandTimeout
        )
    }

    /// A persistent PTY terminal rendered by SwiftTerm.
    public static func interactive(
        initialWorkingDirectory: String = "/root"
    ) -> PocketRootTerminalConfiguration {
        PocketRootTerminalConfiguration(
            placeholderText: "",
            prompt: "",
            allowsInput: true,
            showsAccessoryView: false,
            initialWorkingDirectory: initialWorkingDirectory
        )
    }

    func resolvingInteractiveSessionConfiguration(
        _ sessionConfiguration: PocketRootSessionConfiguration?
    ) -> PocketRootSessionConfiguration {
        sessionConfiguration ?? PocketRootSessionConfiguration(
            workingDirectory: initialWorkingDirectory
        )
    }
}
