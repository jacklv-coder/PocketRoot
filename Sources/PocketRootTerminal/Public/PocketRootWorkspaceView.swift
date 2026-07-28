#if canImport(SwiftUI) && canImport(UIKit)
import PocketRootCore
import SwiftUI

/// A ready-to-embed SwiftUI workspace with persistent Terminal and Files tabs.
@available(iOS 18.0, *)
public struct PocketRootWorkspaceView: View {
    private let system: PocketRootSystem
    private let configuration: PocketRootWorkspaceConfiguration
    private let onTerminalSessionEnded:
        ((PocketRootTerminalSessionEndReason) -> Void)?

    @State private var selectedSurface: PocketRootWorkspaceSurface

    public init(
        system: PocketRootSystem,
        configuration: PocketRootWorkspaceConfiguration = .init(),
        onTerminalSessionEnded:
            ((PocketRootTerminalSessionEndReason) -> Void)? = nil
    ) {
        self.system = system
        self.configuration = configuration
        self.onTerminalSessionEnded = onTerminalSessionEnded
        _selectedSurface = State(initialValue: configuration.initialSurface)
    }

    public var body: some View {
        TabView(selection: $selectedSurface) {
            PocketRootTerminalView(
                system: system,
                sessionConfiguration:
                    configuration.terminalSessionConfiguration,
                configuration: configuration.terminalConfiguration,
                theme: configuration.terminalTheme,
                onSessionEnded: onTerminalSessionEnded
            )
            .tag(PocketRootWorkspaceSurface.terminal)
            .tabItem {
                Label("Terminal", systemImage: "terminal")
            }
            .accessibilityIdentifier("PocketRootWorkspace.terminal")

            NavigationStack {
                PocketRootFileBrowserView(
                    system: system,
                    initialPath: configuration.initialFilePath
                )
            }
            .tag(PocketRootWorkspaceSurface.files)
            .tabItem {
                Label("Files", systemImage: "folder")
            }
            .accessibilityIdentifier("PocketRootWorkspace.files")
        }
        .accessibilityIdentifier("PocketRootWorkspace")
    }
}
#endif
