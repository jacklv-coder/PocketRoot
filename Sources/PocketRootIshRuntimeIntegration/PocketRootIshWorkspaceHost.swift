import Foundation
import PocketRootCore
import PocketRootResources
import PocketRootTerminal

/// Process-lifetime owner for the smallest RootFS-to-Workspace integration.
///
/// Retain one host from the application or scene owner. Calling ``boot()``
/// verifies and installs the caller-supplied RootFS archive, boots the
/// process-global iSH runtime, and coalesces concurrent callers. On iOS,
/// ``makeTerminalViewController()``, ``makeFilesViewController()``,
/// ``makeViewController()``, and ``PocketRootIshWorkspaceView`` automatically
/// boot this host and present ready-made Terminal, Files, or combined
/// Workspace screens.
///
/// Removing a Terminal or Workspace closes only its PTY so another screen can
/// be opened with the same runtime. Call ``shutdown()`` once when the host
/// intentionally terminates the process-global runtime.
@available(macOS 13.0, *)
@MainActor
public final class PocketRootIshWorkspaceHost {
    public let runtimeConfiguration:
        PocketRootIshRuntimeControllerConfiguration
    public let workspaceConfiguration: PocketRootWorkspaceConfiguration

    /// Called synchronously on the main actor whenever the runtime phase
    /// changes.
    public var onPhaseChange: ((PocketRootIshRuntimePhase) -> Void)?

    private let runtimeController: PocketRootIshRuntimeController
    private var bootTask: Task<PocketRootSystem, Error>?
    private var shutdownTask: Task<Void, Error>?

    #if canImport(SwiftUI) && canImport(UIKit)
    private var workspaceControllers: [
        WeakWorkspaceController
    ] = []
    #endif

    public init(
        runtimeConfiguration:
            PocketRootIshRuntimeControllerConfiguration,
        workspaceConfiguration:
            PocketRootWorkspaceConfiguration = .init()
    ) {
        self.runtimeConfiguration = runtimeConfiguration
        self.workspaceConfiguration = workspaceConfiguration
        runtimeController = PocketRootIshRuntimeController(
            configuration: runtimeConfiguration
        )
        bindRuntimeController()
    }

    init(
        runtimeController: PocketRootIshRuntimeController,
        workspaceConfiguration:
            PocketRootWorkspaceConfiguration = .init()
    ) {
        runtimeConfiguration = runtimeController.configuration
        self.workspaceConfiguration = workspaceConfiguration
        self.runtimeController = runtimeController
        bindRuntimeController()
    }

    public var phase: PocketRootIshRuntimePhase {
        if shutdownTask != nil, runtimeController.phase != .terminated {
            return .shuttingDown
        }
        return runtimeController.phase
    }

    public var readySystem: PocketRootSystem? {
        guard shutdownTask == nil else {
            return nil
        }
        return runtimeController.readySystem
    }

    public var installation: PocketRootRootFSInstallation? {
        runtimeController.installation
    }

    public var canBoot: Bool {
        shutdownTask == nil && runtimeController.canBoot
    }

    public var canShutdown: Bool {
        shutdownTask == nil && runtimeController.canShutdown
    }

    /// Whether a new integrated screen may boot or attach a Workspace.
    public var canOpenWorkspace: Bool {
        guard shutdownTask == nil else {
            return false
        }
        switch runtimeController.phase {
        case .unavailable, .shuttingDown, .terminated:
            return false
        case .failed:
            return runtimeController.canBoot
        default:
            return true
        }
    }

    /// Prepares and boots the runtime, joining an existing boot when one is
    /// already in progress.
    @discardableResult
    public func boot() async throws -> PocketRootSystem {
        if let readySystem {
            return readySystem
        }
        if let shutdownTask {
            _ = try await shutdownTask.value
            throw PocketRootIshRuntimeControllerError.lifecycleInProgress(
                runtimeController.phase
            )
        }
        if let bootTask {
            return try await bootTask.value
        }

        let task = Task { @MainActor [runtimeController] in
            try await runtimeController.boot()
        }
        bootTask = task
        defer {
            bootTask = nil
        }
        return try await task.value
    }

    public func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult {
        guard shutdownTask == nil else {
            throw PocketRootIshRuntimeControllerError.lifecycleInProgress(
                .shuttingDown
            )
        }
        return try await runtimeController.execute(request)
    }

    public func refreshRuntimeState() async {
        await runtimeController.refreshRuntimeState()
    }

    /// Closes the PTY in every Terminal or Workspace screen made by this host
    /// without shutting down the shared runtime.
    public func closeWorkspaces(
        completion: (@MainActor () -> Void)? = nil
    ) {
        let controllers = workspaceControllerSnapshot()
        Task { @MainActor [self, controllers] in
            await closeWorkspaceSessions(controllers)
            completion?()
        }
    }

    /// Closes all screens made by this host and then performs the terminal
    /// process-global runtime shutdown. Repeated calls join the same operation;
    /// a successfully terminated host treats later calls as no-ops.
    public func shutdown() async throws {
        if phase == .terminated {
            return
        }
        if let shutdownTask {
            return try await shutdownTask.value
        }

        let controllers = workspaceControllerSnapshot()
        let task = Task { @MainActor [self, controllers] in
            if let bootTask {
                _ = try await bootTask.value
            }
            await closeWorkspaceSessions(controllers)
            if phase == .terminated {
                return
            }
            try await runtimeController.shutdown()
        }
        shutdownTask = task
        publish(.shuttingDown)
        defer {
            shutdownTask = nil
            if runtimeController.phase != .terminated {
                publish(runtimeController.phase)
            }
        }
        try await task.value
    }

    private func bindRuntimeController() {
        runtimeController.onPhaseChange = { [weak self] _ in
            guard let self else {
                return
            }
            publish(self.phase)
        }
    }

    private func publish(_ phase: PocketRootIshRuntimePhase) {
        onPhaseChange?(phase)
        notifyWorkspaceControllers(of: phase)
    }

    #if canImport(SwiftUI) && canImport(UIKit)
    func register(
        _ controller: PocketRootIshWorkspaceViewController
    ) {
        pruneWorkspaceControllers()
        workspaceControllers.append(
            WeakWorkspaceController(controller)
        )
    }

    func unregister(
        _ controller: PocketRootIshWorkspaceViewController
    ) {
        workspaceControllers.removeAll {
            $0.value == nil || $0.value === controller
        }
    }

    private func notifyWorkspaceControllers(
        of phase: PocketRootIshRuntimePhase
    ) {
        pruneWorkspaceControllers()
        for controller in workspaceControllers {
            controller.value?.runtimePhaseDidChange(phase)
        }
    }

    private func workspaceControllerSnapshot() -> [
        PocketRootIshWorkspaceViewController
    ] {
        pruneWorkspaceControllers()
        return workspaceControllers.compactMap(\.value)
    }

    private func closeWorkspaceSessions(
        _ controllers: [PocketRootIshWorkspaceViewController]
    ) async {
        guard !controllers.isEmpty else {
            return
        }
        await withCheckedContinuation { continuation in
            var remaining = controllers.count
            for controller in controllers {
                controller.closeSession {
                    remaining -= 1
                    if remaining == 0 {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func pruneWorkspaceControllers() {
        workspaceControllers.removeAll { $0.value == nil }
    }
    #else
    private func notifyWorkspaceControllers(
        of _: PocketRootIshRuntimePhase
    ) {}

    private func workspaceControllerSnapshot() -> [Never] {
        []
    }

    private func closeWorkspaceSessions(_: [Never]) async {}
    #endif
}

#if canImport(SwiftUI) && canImport(UIKit)
@available(iOS 18.0, *)
@MainActor
private final class WeakWorkspaceController {
    weak var value: PocketRootIshWorkspaceViewController?

    init(_ value: PocketRootIshWorkspaceViewController) {
        self.value = value
    }
}
#endif
