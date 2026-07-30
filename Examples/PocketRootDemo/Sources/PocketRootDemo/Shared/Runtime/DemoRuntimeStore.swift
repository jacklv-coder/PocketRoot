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
    private var runtimeController: PocketRootIshRuntimeController?

    private(set) var phase: DemoRuntimePhase

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
        if let runtimeController {
            return runtimeController.canBoot
        }
        switch phase {
        case .idle, .failed:
            return true
        default:
            return false
        }
    }

    var canShutdown: Bool {
        runtimeController?.canShutdown == true
    }

    var readySystem: PocketRootSystem? {
        runtimeController?.readySystem
    }

    var system: PocketRootSystem? {
        runtimeController?.system
    }

    var installation: PocketRootRootFSInstallation? {
        runtimeController?.installation
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
            let applicationSupportURL = try makeApplicationSupportURL()
            let controller = runtimeController ?? PocketRootIshRuntimeController(
                configuration: PocketRootIshRuntimeControllerConfiguration(
                    archiveURL: archiveURL,
                    applicationSupportURL: applicationSupportURL,
                    workDirectory: "/"
                )
            )
            if runtimeController == nil {
                runtimeController = controller
                controller.onPhaseChange = { [weak self] phase in
                    self?.publish(Self.demoPhase(for: phase))
                }
            }
            try await controller.boot()
        } catch {
            if runtimeController == nil {
                publish(.failed(error.localizedDescription))
            }
        }
    }

    func shutdown() async -> String? {
        guard let runtimeController, canShutdown else {
            return nil
        }

        do {
            try await runtimeController.shutdown()
            return nil
        } catch {
            let failure = error.localizedDescription
            return failure
        }
    }

    func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult {
        guard let runtimeController else {
            throw DemoRuntimeStoreError.runtimeNotReady
        }
        return try await runtimeController.execute(request)
    }

    func refreshRuntimeState() async {
        await runtimeController?.refreshRuntimeState()
    }

    static func demoPhase(
        for phase: PocketRootIshRuntimePhase
    ) -> DemoRuntimePhase {
        switch phase {
        case .unavailable:
            .runtimeUnavailable
        case .idle:
            .idle
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
