import Foundation
import PocketRootCore
import PocketRootIshRuntime
import PocketRootResources

/// The host-visible lifecycle of the process-global iSH runtime.
public enum PocketRootIshRuntimePhase: Sendable, Equatable {
    case unavailable
    case idle
    case preparingRootFS
    case booting
    case ready
    case shuttingDown
    case terminated
    case failed(String)
}

/// Configuration retained by ``PocketRootIshRuntimeController``.
public struct PocketRootIshRuntimeControllerConfiguration: Sendable {
    public let archiveURL: URL
    public let applicationSupportURL: URL
    public let manifest: PocketRootRootFSArtifactManifest
    public let systemConfiguration: PocketRootConfiguration?
    public let workDirectory: String
    public let supervisorGuestPath: String?
    public let kernelLogFileDescriptor: Int32
    public let maximumStandardInputBytes: Int
    public let maximumStandardOutputBytes: Int
    public let maximumStandardErrorBytes: Int
    public let healthCheck: PocketRootIshRuntimeHealthCheckConfiguration?

    public init(
        archiveURL: URL,
        applicationSupportURL: URL,
        manifest: PocketRootRootFSArtifactManifest = .ishEmbedV0_3_3,
        systemConfiguration: PocketRootConfiguration? = nil,
        workDirectory: String = "/",
        supervisorGuestPath: String? = nil,
        kernelLogFileDescriptor: Int32 = -1,
        maximumStandardInputBytes: Int = 1 * 1_024 * 1_024,
        maximumStandardOutputBytes: Int = 8 * 1_024 * 1_024,
        maximumStandardErrorBytes: Int = 4 * 1_024 * 1_024,
        healthCheck: PocketRootIshRuntimeHealthCheckConfiguration? = nil
    ) {
        self.archiveURL = archiveURL
        self.applicationSupportURL = applicationSupportURL
        self.manifest = manifest
        self.systemConfiguration = systemConfiguration
        self.workDirectory = workDirectory
        self.supervisorGuestPath = supervisorGuestPath
        self.kernelLogFileDescriptor = kernelLogFileDescriptor
        self.maximumStandardInputBytes = maximumStandardInputBytes
        self.maximumStandardOutputBytes = maximumStandardOutputBytes
        self.maximumStandardErrorBytes = maximumStandardErrorBytes
        self.healthCheck = healthCheck
    }
}

public enum PocketRootIshRuntimeControllerError:
    LocalizedError,
    Sendable,
    Equatable
{
    case runtimeUnavailable
    case lifecycleInProgress(PocketRootIshRuntimePhase)
    case runtimeNotReady
    case unexpectedState(PocketRootRuntimeState)

    public var errorDescription: String? {
        switch self {
        case .runtimeUnavailable:
            "The arm64 IshEmbed runtime is unavailable in this build."
        case .lifecycleInProgress(let phase):
            "The iSH runtime cannot start another lifecycle operation from \(phase)."
        case .runtimeNotReady:
            "Boot the iSH runtime before using this feature."
        case .unexpectedState(let state):
            "The iSH runtime reached an unexpected state: \(state)."
        }
    }
}

/// A small host-app facade for RootFS preparation and iSH lifecycle ownership.
///
/// Retain one controller for the lifetime of the host process, call ``boot()``
/// once, then pass ``readySystem`` to terminal and file-browser views. A
/// successful ``shutdown()`` is terminal for the current host process.
@available(macOS 13.0, *)
@MainActor
public final class PocketRootIshRuntimeController {
    typealias SystemPreparer = @Sendable (
        PocketRootIshRuntimeControllerConfiguration
    ) async throws -> PocketRootPreparedIshSystem

    public let configuration: PocketRootIshRuntimeControllerConfiguration

    public private(set) var phase: PocketRootIshRuntimePhase
    public private(set) var preparedSystem: PocketRootPreparedIshSystem?

    /// Called synchronously on the main actor whenever ``phase`` changes.
    public var onPhaseChange: ((PocketRootIshRuntimePhase) -> Void)?

    private let runtimeAvailable: Bool
    private let prepareSystem: SystemPreparer
    private var retryAllowed = true
    private var phaseGeneration: UInt64 = 0

    public init(
        configuration: PocketRootIshRuntimeControllerConfiguration
    ) {
        self.configuration = configuration
        runtimeAvailable = PocketRootIshRuntimeFactory.isAvailable
        phase = runtimeAvailable ? .idle : .unavailable
        prepareSystem = { configuration in
            try await Self.prepareSystem(configuration: configuration)
        }
    }

    init(
        configuration: PocketRootIshRuntimeControllerConfiguration,
        runtimeAvailable: Bool,
        prepareSystem: @escaping SystemPreparer
    ) {
        self.configuration = configuration
        self.runtimeAvailable = runtimeAvailable
        phase = runtimeAvailable ? .idle : .unavailable
        self.prepareSystem = prepareSystem
    }

    public var system: PocketRootSystem? {
        preparedSystem?.system
    }

    public var installation: PocketRootRootFSInstallation? {
        preparedSystem?.installation
    }

    public var readySystem: PocketRootSystem? {
        phase == .ready ? system : nil
    }

    public var canBoot: Bool {
        guard runtimeAvailable, retryAllowed else {
            return false
        }
        switch phase {
        case .idle, .failed:
            return true
        default:
            return false
        }
    }

    public var canShutdown: Bool {
        phase == .ready
    }

    /// Prepares the configured archive when necessary, boots iSH, and returns
    /// the system that terminal and file-browser views must share.
    @discardableResult
    public func boot() async throws -> PocketRootSystem {
        guard runtimeAvailable else {
            publish(.unavailable)
            throw PocketRootIshRuntimeControllerError.runtimeUnavailable
        }
        guard canBoot else {
            throw PocketRootIshRuntimeControllerError.lifecycleInProgress(phase)
        }

        do {
            let prepared: PocketRootPreparedIshSystem
            if let preparedSystem {
                prepared = preparedSystem
            } else {
                publish(.preparingRootFS)
                prepared = try await prepareSystem(configuration)
                preparedSystem = prepared
            }

            retryAllowed = false
            publish(.booting)
            try await prepared.system.boot()
            let state = await prepared.system.state
            guard state == .ready else {
                throw PocketRootIshRuntimeControllerError.unexpectedState(state)
            }
            publish(.ready)
            return prepared.system
        } catch {
            await reconcileAfterFailure(error)
            throw error
        }
    }

    public func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult {
        guard let system = readySystem else {
            throw PocketRootIshRuntimeControllerError.runtimeNotReady
        }
        do {
            return try await system.execute(request)
        } catch {
            await refreshRuntimeState()
            throw error
        }
    }

    /// Refreshes the facade from the authoritative runtime state. Transient
    /// lifecycle phases are preserved so another operation cannot be admitted
    /// while the underlying async call is suspended.
    public func refreshRuntimeState() async {
        guard let system else {
            return
        }
        switch phase {
        case .preparingRootFS, .booting, .shuttingDown:
            return
        default:
            break
        }
        phaseGeneration &+= 1
        let refreshGeneration = phaseGeneration
        let state = await system.state
        guard refreshGeneration == phaseGeneration else {
            return
        }
        publish(Self.phase(for: state))
    }

    /// Performs bounded native shutdown. Success means this host process must
    /// be restarted before iSH can boot again.
    public func shutdown() async throws {
        guard let system = readySystem else {
            throw PocketRootIshRuntimeControllerError.runtimeNotReady
        }
        publish(.shuttingDown)
        do {
            try await system.shutdown()
            retryAllowed = false
            publish(.terminated)
        } catch {
            let state = await system.state
            publish(Self.phase(for: state, fallbackFailure: error.localizedDescription))
            throw error
        }
    }

    static func phase(
        for state: PocketRootRuntimeState,
        fallbackFailure: String? = nil
    ) -> PocketRootIshRuntimePhase {
        switch state {
        case .idle:
            fallbackFailure.map(PocketRootIshRuntimePhase.failed) ?? .idle
        case .preparingRootFS:
            .preparingRootFS
        case .booting:
            .booting
        case .ready:
            .ready
        case .shuttingDown:
            .shuttingDown
        case .terminated:
            .terminated
        case .failed(let message):
            .failed(message)
        }
    }

    private func reconcileAfterFailure(_ error: Error) async {
        guard let system else {
            retryAllowed = true
            publish(.failed(error.localizedDescription))
            return
        }
        let state = await system.state
        retryAllowed = state == .idle
        publish(Self.phase(for: state, fallbackFailure: error.localizedDescription))
    }

    private func publish(_ phase: PocketRootIshRuntimePhase) {
        phaseGeneration &+= 1
        self.phase = phase
        onPhaseChange?(phase)
    }

    private static func prepareSystem(
        configuration: PocketRootIshRuntimeControllerConfiguration
    ) async throws -> PocketRootPreparedIshSystem {
        try await PocketRootIshSystemFactory.prepareSystem(
            archiveURL: configuration.archiveURL,
            applicationSupportURL: configuration.applicationSupportURL,
            manifest: configuration.manifest,
            systemConfiguration: configuration.systemConfiguration,
            workDirectory: configuration.workDirectory,
            supervisorGuestPath: configuration.supervisorGuestPath,
            kernelLogFileDescriptor: configuration.kernelLogFileDescriptor,
            maximumStandardInputBytes: configuration.maximumStandardInputBytes,
            maximumStandardOutputBytes: configuration.maximumStandardOutputBytes,
            maximumStandardErrorBytes: configuration.maximumStandardErrorBytes,
            healthCheck: configuration.healthCheck
        )
    }
}
