import Foundation
import PocketRoot
import PocketRootIshRuntime
import PocketRootIshRuntimeIntegration

@MainActor
protocol DemoRuntimeStoreObserver: AnyObject {
    func demoRuntimeStoreDidChange(_ store: DemoRuntimeStore)
}

struct DemoDiagnosticStatus: Equatable {
    let text: String
    let isReady: Bool
}

enum DemoRuntimePhase: Equatable {
    case rootFSMissing
    case runtimeUnavailable
    case idle
    case preparingRootFS
    case booting
    case ready
    case shuttingDown
    case terminated
    case failed(String)

    var displayName: String {
        switch self {
        case .rootFSMissing:
            "RootFS Missing"
        case .runtimeUnavailable:
            "Runtime Unavailable"
        case .idle:
            "Ready to Boot"
        case .preparingRootFS:
            "Preparing RootFS"
        case .booting:
            "Booting"
        case .ready:
            "Ready"
        case .shuttingDown:
            "Shutting Down"
        case .terminated:
            "Restart App to Boot Again"
        case .failed(let message):
            "Failed: \(message)"
        }
    }
}

enum DemoRuntimeStoreError: LocalizedError {
    case rootFSMissing
    case runtimeUnavailable
    case runtimeNotReady
    case unexpectedState(PocketRootRuntimeState)

    var errorDescription: String? {
        switch self {
        case .rootFSMissing:
            "The reviewed RootFS was not injected into this Debug build."
        case .runtimeUnavailable:
            "The arm64 IshEmbed runtime is not available in this build."
        case .runtimeNotReady:
            "Boot the runtime before using this feature."
        case .unexpectedState(let state):
            "The runtime finished booting in an unexpected state: \(state)."
        }
    }
}

@MainActor
final class DemoRuntimeStore {
    static let shared = DemoRuntimeStore()

    static let rootFSResourceName = "pocketroot-fs-v0.3.3"
    static let rootFSResourceExtension = "tar.gz"

    private final class WeakObserver {
        weak var value: (any DemoRuntimeStoreObserver)?

        init(_ value: any DemoRuntimeStoreObserver) {
            self.value = value
        }
    }

    private let bundle: Bundle
    private let fileManager: FileManager
    private let runtimeAvailable: Bool
    private let applicationSupportURLOverride: URL?
    private var observers: [WeakObserver] = []

    private(set) var phase: DemoRuntimePhase
    private(set) var system: PocketRootSystem?
    private(set) var installation: PocketRootRootFSInstallation?

    init(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        runtimeAvailable: Bool = PocketRootIshRuntimeFactory.isAvailable,
        applicationSupportURL: URL? = nil
    ) {
        self.bundle = bundle
        self.fileManager = fileManager
        self.runtimeAvailable = runtimeAvailable
        applicationSupportURLOverride = applicationSupportURL

        if !runtimeAvailable {
            phase = .runtimeUnavailable
        } else if bundle.url(
            forResource: Self.rootFSResourceName,
            withExtension: Self.rootFSResourceExtension
        ) == nil {
            phase = .rootFSMissing
        } else {
            phase = .idle
        }
    }

    var rootFSArchiveURL: URL? {
        bundle.url(
            forResource: Self.rootFSResourceName,
            withExtension: Self.rootFSResourceExtension
        )
    }

    var canBoot: Bool {
        switch phase {
        case .idle:
            true
        case .failed:
            system == nil
        default:
            false
        }
    }

    var canShutdown: Bool {
        phase == .ready
    }

    var readySystem: PocketRootSystem? {
        phase == .ready ? system : nil
    }

    var rootFSStatus: DemoDiagnosticStatus {
        if let installation {
            return DemoDiagnosticStatus(
                text: installation.reusedExistingInstallation
                    ? "Installed (Reused)"
                    : "Installed",
                isReady: true
            )
        }
        if rootFSArchiveURL != nil {
            return DemoDiagnosticStatus(text: "Embedded", isReady: true)
        }
        return DemoDiagnosticStatus(text: "Missing", isReady: false)
    }

    var runtimeStatus: DemoDiagnosticStatus {
        guard runtimeAvailable else {
            return DemoDiagnosticStatus(text: "Unavailable", isReady: false)
        }
        switch phase {
        case .preparingRootFS:
            return DemoDiagnosticStatus(text: "Preparing", isReady: false)
        case .booting:
            return DemoDiagnosticStatus(text: "Booting", isReady: false)
        case .ready:
            return DemoDiagnosticStatus(text: "Ready", isReady: true)
        case .shuttingDown:
            return DemoDiagnosticStatus(text: "Shutting Down", isReady: false)
        case .terminated:
            return DemoDiagnosticStatus(text: "Terminated", isReady: false)
        case .failed:
            return DemoDiagnosticStatus(text: "Failed", isReady: false)
        case .rootFSMissing, .runtimeUnavailable, .idle:
            return DemoDiagnosticStatus(text: "Available", isReady: true)
        }
    }

    func addObserver(_ observer: any DemoRuntimeStoreObserver) {
        observers.removeAll { $0.value == nil || $0.value === observer }
        observers.append(WeakObserver(observer))
        observer.demoRuntimeStoreDidChange(self)
    }

    func removeObserver(_ observer: any DemoRuntimeStoreObserver) {
        observers.removeAll { $0.value == nil || $0.value === observer }
    }

    func boot() async {
        guard canBoot else {
            return
        }
        guard runtimeAvailable else {
            publish(.runtimeUnavailable)
            return
        }
        guard let archiveURL = rootFSArchiveURL else {
            publish(.rootFSMissing)
            return
        }

        do {
            publish(.preparingRootFS)
            let applicationSupportURL = try makeApplicationSupportURL()
            let prepared = try await PocketRootIshSystemFactory.prepareSystem(
                archiveURL: archiveURL,
                applicationSupportURL: applicationSupportURL,
                manifest: .ishEmbedV0_3_3,
                workDirectory: "/"
            )
            installation = prepared.installation
            system = prepared.system

            publish(.booting)
            try await prepared.system.boot()
            let state = await prepared.system.state
            guard state == .ready else {
                throw DemoRuntimeStoreError.unexpectedState(state)
            }
            publish(.ready)
        } catch {
            publish(.failed(error.localizedDescription))
        }
    }

    func shutdown() async -> String? {
        guard let system, canShutdown else {
            return nil
        }

        publish(.shuttingDown)
        do {
            try await system.shutdown()
            publish(.terminated)
            return nil
        } catch {
            let failure = error.localizedDescription
            await reconcileRuntimeState(
                fallbackFailure: failure
            )
            return failure
        }
    }

    func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult {
        guard let system = readySystem else {
            throw DemoRuntimeStoreError.runtimeNotReady
        }
        do {
            return try await system.execute(request)
        } catch {
            await refreshRuntimeState()
            throw error
        }
    }

    func refreshRuntimeState() async {
        guard system != nil else {
            return
        }
        switch phase {
        case .preparingRootFS, .booting, .shuttingDown:
            // PocketRootSystem deliberately exposes only the last stable
            // state while a lifecycle call is suspended. Keep the Demo's
            // transient phase so controls cannot admit a second lifecycle.
            return
        default:
            break
        }
        await reconcileRuntimeState()
    }

    static func reconciledPhase(
        for state: PocketRootRuntimeState,
        hasInstallation: Bool,
        fallbackFailure: String? = nil
    ) -> DemoRuntimePhase? {
        switch state {
        case .idle:
            hasInstallation
                ? .idle
                : fallbackFailure.map(DemoRuntimePhase.failed)
        case .ready:
            .ready
        case .terminated:
            .terminated
        case .failed(let message):
            .failed(message)
        case .preparingRootFS:
            .preparingRootFS
        case .booting:
            .booting
        case .shuttingDown:
            .shuttingDown
        }
    }

    private func reconcileRuntimeState(
        fallbackFailure: String? = nil
    ) async {
        guard let system else {
            if let fallbackFailure {
                publish(.failed(fallbackFailure))
            }
            return
        }
        let state = await system.state
        if let reconciledPhase = Self.reconciledPhase(
            for: state,
            hasInstallation: installation != nil,
            fallbackFailure: fallbackFailure
        ) {
            publish(reconciledPhase)
        }
    }

    private func makeApplicationSupportURL() throws -> URL {
        if let applicationSupportURLOverride {
            try fileManager.createDirectory(
                at: applicationSupportURLOverride,
                withIntermediateDirectories: true
            )
            return applicationSupportURLOverride
        }
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let applicationSupportURL = baseURL.appendingPathComponent(
            "PocketRootDemo",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = applicationSupportURL
        try mutableURL.setResourceValues(resourceValues)
        return applicationSupportURL
    }

    private func publish(_ phase: DemoRuntimePhase) {
        self.phase = phase
        observers.removeAll { $0.value == nil }
        for observer in observers {
            observer.value?.demoRuntimeStoreDidChange(self)
        }
    }
}
