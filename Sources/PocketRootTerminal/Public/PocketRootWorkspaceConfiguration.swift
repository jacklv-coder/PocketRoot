import Foundation
import PocketRootCore

/// The first surface shown by a PocketRoot workspace.
public enum PocketRootWorkspaceSurface: Int, Sendable, Equatable, CaseIterable {
    case terminal
    case files
}

/// Configuration shared by the UIKit and SwiftUI workspace containers.
///
/// The workspace never prepares or boots a runtime. The host remains
/// responsible for supplying one already-ready ``PocketRootSystem``.
public struct PocketRootWorkspaceConfiguration: Sendable, Equatable {
    public let terminalConfiguration: PocketRootTerminalConfiguration
    public let terminalSessionConfiguration: PocketRootSessionConfiguration?
    public let terminalTheme: PocketRootTerminalTheme
    public let initialFilePath: String
    public let initialSurface: PocketRootWorkspaceSurface
    public let allowsFileOperations: Bool

    public init(
        terminalConfiguration: PocketRootTerminalConfiguration = .interactive(),
        terminalSessionConfiguration: PocketRootSessionConfiguration? = nil,
        terminalTheme: PocketRootTerminalTheme = .dark,
        initialFilePath: String = "/root",
        initialSurface: PocketRootWorkspaceSurface = .terminal,
        allowsFileOperations: Bool = true
    ) {
        self.terminalConfiguration = terminalConfiguration
        self.terminalSessionConfiguration = terminalSessionConfiguration
        self.terminalTheme = terminalTheme
        self.initialFilePath = initialFilePath
        self.initialSurface = initialSurface
        self.allowsFileOperations = allowsFileOperations
    }
}
