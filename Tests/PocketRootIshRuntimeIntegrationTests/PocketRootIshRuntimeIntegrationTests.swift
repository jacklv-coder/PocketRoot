import Darwin
import Foundation
import PocketRootResources
import PocketRootTerminal
import XCTest
@testable import PocketRootCore
@_spi(PocketRootRuntimeSmoke) @testable import PocketRootIshRuntimeIntegration

@available(macOS 13.0, *)
final class PocketRootIshRuntimeIntegrationTests: XCTestCase {
    @MainActor
    func testControllerRejectsUnavailableRuntime() async throws {
        let configuration = makeControllerConfiguration()
        let controller = PocketRootIshRuntimeController(
            configuration: configuration,
            runtimeAvailable: false,
            prepareSystem: { _ in
                XCTFail("Unavailable runtime must fail before RootFS preparation.")
                throw CocoaError(.fileReadUnknown)
            }
        )

        XCTAssertEqual(controller.phase, .unavailable)
        XCTAssertFalse(controller.canBoot)
        do {
            _ = try await controller.boot()
            XCTFail("Unavailable runtime unexpectedly booted.")
        } catch let error as PocketRootIshRuntimeControllerError {
            XCTAssertEqual(error, .runtimeUnavailable)
        }
    }

    @MainActor
    func testControllerPreparationFailureIsObservableAndRetryable() async {
        let expectedError = CocoaError(.fileReadCorruptFile)
        let controller = PocketRootIshRuntimeController(
            configuration: makeControllerConfiguration(),
            runtimeAvailable: true,
            prepareSystem: { _ in
                throw expectedError
            }
        )
        var observedPhases: [PocketRootIshRuntimePhase] = []
        controller.onPhaseChange = {
            observedPhases.append($0)
        }

        do {
            _ = try await controller.boot()
            XCTFail("The injected preparation failure unexpectedly booted.")
        } catch {
            XCTAssertEqual(
                (error as NSError).code,
                (expectedError as NSError).code
            )
        }

        XCTAssertEqual(observedPhases.first, .preparingRootFS)
        guard case .failed = controller.phase else {
            return XCTFail("Preparation failure was not published.")
        }
        XCTAssertTrue(controller.canBoot)
        XCTAssertNil(controller.system)
        XCTAssertNil(controller.readySystem)
    }

    @MainActor
    func testControllerMapsAuthoritativeRuntimeStates() {
        XCTAssertEqual(
            PocketRootIshRuntimeController.phase(for: .idle),
            .idle
        )
        XCTAssertEqual(
            PocketRootIshRuntimeController.phase(
                for: .idle,
                fallbackFailure: "retry later"
            ),
            .failed("retry later")
        )
        XCTAssertEqual(
            PocketRootIshRuntimeController.phase(for: .ready),
            .ready
        )
        XCTAssertEqual(
            PocketRootIshRuntimeController.phase(for: .failed("transport")),
            .failed("transport")
        )
        XCTAssertEqual(
            PocketRootIshRuntimeController.phase(for: .terminated),
            .terminated
        )
    }

    @MainActor
    func testWorkspaceHostCoalescesBootAndMakesShutdownIdempotent() async throws {
        let runtime = WorkspaceHostLinuxRuntime()
        let system = PocketRootSystem(runtime: runtime)
        let preparationGate = WorkspaceHostPreparationGate()
        let controller = PocketRootIshRuntimeController(
            configuration: makeControllerConfiguration(),
            runtimeAvailable: true,
            prepareSystem: { _ in
                await preparationGate.enter()
                return PocketRootPreparedIshSystem(
                    system: system,
                    installation: PocketRootRootFSInstallation(
                        version: "fixture-v1",
                        rootFSURL: URL(
                            fileURLWithPath: "/tmp/fixture-rootfs"
                        ),
                        reusedExistingInstallation: false
                    )
                )
            }
        )
        let host = PocketRootIshWorkspaceHost(
            runtimeController: controller,
            workspaceConfiguration: PocketRootWorkspaceConfiguration(
                initialFilePath: "/workspace",
                initialSurface: .files
            )
        )
        var observedPhases: [PocketRootIshRuntimePhase] = []
        host.onPhaseChange = {
            observedPhases.append($0)
        }

        let firstBoot = Task {
            try await host.boot()
        }
        await preparationGate.waitUntilEntered()
        let secondBoot = Task {
            try await host.boot()
        }
        await Task.yield()
        await preparationGate.resume()

        let firstSystem = try await firstBoot.value
        let secondSystem = try await secondBoot.value
        let preparationCount = await preparationGate.entryCount
        let bootCount = await runtime.bootCount
        XCTAssertTrue(firstSystem === secondSystem)
        XCTAssertEqual(preparationCount, 1)
        XCTAssertEqual(bootCount, 1)
        XCTAssertEqual(host.phase, .ready)
        XCTAssertEqual(
            host.workspaceConfiguration.initialFilePath,
            "/workspace"
        )
        XCTAssertEqual(
            host.workspaceConfiguration.initialSurface,
            .files
        )
        XCTAssertEqual(
            observedPhases,
            [.preparingRootFS, .booting, .ready]
        )

        XCTAssertTrue(host.canOpenWorkspace)
        let shutdownPhaseStart = observedPhases.count
        await runtime.suspendNextShutdown()
        let shutdownTask = Task {
            try await host.shutdown()
        }
        await runtime.waitUntilShutdownEntered()
        XCTAssertEqual(host.phase, .shuttingDown)
        XCTAssertNil(host.readySystem)
        XCTAssertFalse(host.canOpenWorkspace)
        XCTAssertFalse(host.canShutdown)

        let lateBoot = Task {
            try await host.boot()
        }
        await Task.yield()
        await runtime.resumeShutdown()
        try await shutdownTask.value
        do {
            _ = try await lateBoot.value
            XCTFail("A boot admitted after shutdown should fail.")
        } catch let error as PocketRootIshRuntimeControllerError {
            XCTAssertEqual(error, .lifecycleInProgress(.terminated))
        }

        try await host.shutdown()
        let shutdownCount = await runtime.shutdownCount
        XCTAssertEqual(shutdownCount, 1)
        XCTAssertEqual(host.phase, .terminated)
        XCTAssertFalse(
            observedPhases[shutdownPhaseStart...].contains(.ready)
        )
        XCTAssertFalse(host.canBoot)
        XCTAssertFalse(host.canShutdown)
    }

    @MainActor
    func testWorkspaceHostRejectsScreensAfterTerminalRuntimeFailure() async throws {
        let runtime = WorkspaceHostLinuxRuntime()
        let system = PocketRootSystem(runtime: runtime)
        let controller = PocketRootIshRuntimeController(
            configuration: makeControllerConfiguration(),
            runtimeAvailable: true,
            prepareSystem: { _ in
                PocketRootPreparedIshSystem(
                    system: system,
                    installation: PocketRootRootFSInstallation(
                        version: "fixture-v1",
                        rootFSURL: URL(
                            fileURLWithPath: "/tmp/fixture-rootfs"
                        ),
                        reusedExistingInstallation: false
                    )
                )
            }
        )
        let host = PocketRootIshWorkspaceHost(
            runtimeController: controller
        )

        _ = try await host.boot()
        XCTAssertTrue(host.canOpenWorkspace)

        await runtime.setState(.failed("native runtime requires restart"))
        await host.refreshRuntimeState()

        XCTAssertEqual(
            host.phase,
            .failed("native runtime requires restart")
        )
        XCTAssertFalse(host.canBoot)
        XCTAssertFalse(host.canOpenWorkspace)
    }

    @MainActor
    func testRefreshCannotOverwriteReentrantShutdownPhase() async throws {
        let runtime = RefreshRaceLinuxRuntime()
        let system = PocketRootSystem(runtime: runtime)
        let controller = PocketRootIshRuntimeController(
            configuration: makeControllerConfiguration(),
            runtimeAvailable: true,
            prepareSystem: { _ in
                PocketRootPreparedIshSystem(
                    system: system,
                    installation: PocketRootRootFSInstallation(
                        version: "fixture-v1",
                        rootFSURL: URL(fileURLWithPath: "/tmp/fixture-rootfs"),
                        reusedExistingInstallation: false
                    )
                )
            }
        )

        _ = try await controller.boot()
        XCTAssertEqual(controller.phase, .ready)

        await runtime.suspendNextStateReads(1)
        let refreshTask = Task {
            await controller.refreshRuntimeState()
        }
        await runtime.waitForStateReadToSuspend(0)

        let shutdownTask = Task {
            try await controller.shutdown()
        }
        await runtime.waitForShutdownToSuspend()
        XCTAssertEqual(controller.phase, .shuttingDown)

        await runtime.resumeStateRead(0)
        await refreshTask.value
        XCTAssertEqual(controller.phase, .shuttingDown)
        XCTAssertNil(controller.readySystem)
        XCTAssertFalse(controller.canShutdown)

        await runtime.resumeShutdown()
        try await shutdownTask.value
        XCTAssertEqual(controller.phase, .terminated)
    }

    @MainActor
    func testNewerRefreshWinsWhenStateReadsCompleteOutOfOrder() async throws {
        let runtime = RefreshRaceLinuxRuntime()
        let system = PocketRootSystem(runtime: runtime)
        let controller = PocketRootIshRuntimeController(
            configuration: makeControllerConfiguration(),
            runtimeAvailable: true,
            prepareSystem: { _ in
                PocketRootPreparedIshSystem(
                    system: system,
                    installation: PocketRootRootFSInstallation(
                        version: "fixture-v1",
                        rootFSURL: URL(fileURLWithPath: "/tmp/fixture-rootfs"),
                        reusedExistingInstallation: false
                    )
                )
            }
        )

        _ = try await controller.boot()
        await runtime.suspendNextStateReads(2)

        let olderRefresh = Task {
            await controller.refreshRuntimeState()
        }
        await runtime.waitForStateReadToSuspend(0)

        await runtime.setState(.failed("session transport failed"))
        let newerRefresh = Task {
            await controller.refreshRuntimeState()
        }
        await runtime.waitForStateReadToSuspend(1)

        await runtime.resumeStateRead(0)
        await olderRefresh.value
        XCTAssertEqual(controller.phase, .ready)

        await runtime.resumeStateRead(1)
        await newerRefresh.value
        XCTAssertEqual(controller.phase, .failed("session transport failed"))
    }

    func testFactoryDerivesHealthDefaultFromManifest() {
        XCTAssertEqual(
            PocketRootIshSystemFactory.defaultHealthCheck(for: .ishEmbedV0_3_3),
            .ishEmbedV0_3_3
        )

        let customManifest = PocketRootRootFSArtifactManifest(
            version: "custom-v1",
            architecture: .arm64,
            format: .fakeFSTarGzip,
            downloadURL: URL(string: "https://example.com/custom.tar.gz")!,
            sha256: String(repeating: "0", count: 64)
        )
        XCTAssertEqual(
            PocketRootIshSystemFactory.defaultHealthCheck(for: customManifest),
            .alpineARM64
        )
    }

    func testFactoryPreparesArchiveAndAlignsSystemVersion() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PocketRootIntegrationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let archiveURL = directoryURL.appendingPathComponent("rootfs.tar.gz")
        try XCTUnwrap(Data(base64Encoded: Self.archiveBase64)).write(to: archiveURL)
        let applicationSupportURL = directoryURL.appendingPathComponent(
            "Application Support/PocketRoot",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )
        let manifest = PocketRootRootFSArtifactManifest(
            version: "fixture-v1",
            architecture: .arm64,
            format: .fakeFSTarGzip,
            downloadURL: URL(string: "https://example.com/rootfs.tar.gz")!,
            sha256: "4ede5b57ad2a2ee908076eaed25c3736f3ea9214cc75ba6081f1871b4716a05c",
            archiveByteCount: 171,
            expandedArchiveByteCount: 10_240
        )

        let prepared = try await PocketRootIshSystemFactory.prepareSystem(
            archiveURL: archiveURL,
            applicationSupportURL: applicationSupportURL,
            manifest: manifest,
            systemConfiguration: PocketRootConfiguration(
                rootFSVersion: "must-be-replaced",
                defaultWorkingDirectory: "/srv/vms/default",
                commandTimeout: .seconds(17)
            )
        )

        XCTAssertEqual(prepared.installation.version, "fixture-v1")
        let configuration = await prepared.system.configuration
        XCTAssertEqual(configuration.rootFSVersion, "fixture-v1")
        XCTAssertEqual(configuration.defaultWorkingDirectory, "/srv/vms/default")
        XCTAssertEqual(configuration.commandTimeout, .seconds(17))
        try PocketRootRootFSValidator.validateMaterializedFakeFS(
            at: prepared.installation.rootFSURL
        )
    }

    func testSmokeFailureInjectionCleansUpBeforeNormalRecovery() async throws {
        let fixture = try makeFixture()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fixture.directoryURL)
        }

        do {
            _ = try await PocketRootIshSystemFactory.prepareSystemForFailureInjection(
                archiveURL: fixture.archiveURL,
                applicationSupportURL: fixture.applicationSupportURL,
                manifest: fixture.manifest,
                failureInjection: .insufficientStorage
            )
            XCTFail("The capacity failure injection must reject installation.")
        } catch PocketRootRootFSInstallationError.insufficientStorage(
            let requiredBytes,
            let availableBytes
        ) {
            XCTAssertGreaterThan(requiredBytes, 0)
            XCTAssertEqual(availableBytes, 0)
        }
        try assertNoInstallerResidue(in: fixture.applicationSupportURL)

        do {
            _ = try await PocketRootIshSystemFactory.prepareSystemForFailureInjection(
                archiveURL: fixture.archiveURL,
                applicationSupportURL: fixture.applicationSupportURL,
                manifest: fixture.manifest,
                failureInjection: .gzipENOSPC
            )
            XCTFail("The gzip ENOSPC failure injection must reject installation.")
        } catch PocketRootArchiveExtractionError.gzipDecompressionFailed(let message) {
            XCTAssertTrue(
                message.localizedCaseInsensitiveContains("space"),
                "Unexpected gzip ENOSPC error: \(message)"
            )
        }
        try assertNoInstallerResidue(in: fixture.applicationSupportURL)

        let recovered = try await PocketRootIshSystemFactory.prepareSystem(
            archiveURL: fixture.archiveURL,
            applicationSupportURL: fixture.applicationSupportURL,
            manifest: fixture.manifest
        )
        XCTAssertFalse(recovered.installation.reusedExistingInstallation)
        try PocketRootRootFSValidator.validateMaterializedFakeFS(
            at: recovered.installation.rootFSURL
        )
    }

    private func makeFixture() throws -> (
        directoryURL: URL,
        archiveURL: URL,
        applicationSupportURL: URL,
        manifest: PocketRootRootFSArtifactManifest
    ) {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PocketRootIntegrationFailureTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let archiveURL = directoryURL.appendingPathComponent("rootfs.tar.gz")
        try XCTUnwrap(Data(base64Encoded: Self.archiveBase64)).write(to: archiveURL)
        let applicationSupportURL = directoryURL.appendingPathComponent(
            "Application Support/PocketRoot",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )
        let manifest = PocketRootRootFSArtifactManifest(
            version: "fixture-v1",
            architecture: .arm64,
            format: .fakeFSTarGzip,
            downloadURL: URL(string: "https://example.com/rootfs.tar.gz")!,
            sha256: "4ede5b57ad2a2ee908076eaed25c3736f3ea9214cc75ba6081f1871b4716a05c",
            archiveByteCount: 171,
            expandedArchiveByteCount: 10_240
        )
        return (directoryURL, archiveURL, applicationSupportURL, manifest)
    }

    private func makeControllerConfiguration()
        -> PocketRootIshRuntimeControllerConfiguration
    {
        PocketRootIshRuntimeControllerConfiguration(
            archiveURL: URL(fileURLWithPath: "/tmp/reviewed-rootfs.tar.gz"),
            applicationSupportURL: URL(
                fileURLWithPath: "/tmp/PocketRootHostTests",
                isDirectory: true
            )
        )
    }

    private func assertNoInstallerResidue(in applicationSupportURL: URL) throws {
        let rootFSURL = applicationSupportURL.appendingPathComponent(
            "rootfs",
            isDirectory: true
        )
        let contents = try FileManager.default.contentsOfDirectory(
            at: rootFSURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(
            contents.isEmpty,
            "Failure injection left RootFS entries: \(contents.map(\.lastPathComponent))"
        )
    }

    private static let archiveBase64 =
        "H4sIAAAAAAAC/+3VMQ6CMBiG4R6FE0ArtD1PDRAHjImtice3MAnK4PA3MbzPUoYmDG/4GGOjpOnMW7uc2fb88uzafL2yqoBHTOGeX6mOaYzNdUih7s+y/V3X7fc32/7eaaMqTX9xc/w+pKBw1O9/zi/6E/h9//3JOfa/ZP/LME23Oj2T1P5/dn9rbtf9TWbZ/xKW7swgAAAAAAAAAAAAAPy9F8wBBB8AKAAA"
}

@available(macOS 13.0, *)
private actor WorkspaceHostPreparationGate {
    private(set) var entryCount = 0
    private var entered = false
    private var enterWaiter: CheckedContinuation<Void, Never>?
    private var resumeWaiter: CheckedContinuation<Void, Never>?

    func enter() async {
        entryCount += 1
        entered = true
        enterWaiter?.resume()
        enterWaiter = nil
        await withCheckedContinuation { continuation in
            resumeWaiter = continuation
        }
    }

    func waitUntilEntered() async {
        guard !entered else {
            return
        }
        await withCheckedContinuation { continuation in
            enterWaiter = continuation
        }
    }

    func resume() {
        resumeWaiter?.resume()
        resumeWaiter = nil
    }
}

@available(macOS 13.0, *)
private actor WorkspaceHostLinuxRuntime: LinuxRuntime {
    private var currentState: PocketRootRuntimeState = .idle
    private(set) var bootCount = 0
    private(set) var shutdownCount = 0
    private var shouldSuspendShutdown = false
    private var shutdownEntered = false
    private var shutdownEnteredWaiter: CheckedContinuation<Void, Never>?
    private var shutdownResumeWaiter: CheckedContinuation<Void, Never>?

    var state: PocketRootRuntimeState {
        currentState
    }

    func boot(configuration _: PocketRootConfiguration) async throws {
        bootCount += 1
        currentState = .ready
    }

    func execute(
        _: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult {
        throw PocketRootError.unsupportedOperation("Not used by this test.")
    }

    func makeSession(
        configuration _: PocketRootSessionConfiguration
    ) async throws -> any PocketRootSession {
        throw PocketRootError.unsupportedOperation("Not used by this test.")
    }

    func shutdown() async throws {
        shutdownCount += 1
        if shouldSuspendShutdown {
            shouldSuspendShutdown = false
            shutdownEntered = true
            shutdownEnteredWaiter?.resume()
            shutdownEnteredWaiter = nil
            await withCheckedContinuation { continuation in
                shutdownResumeWaiter = continuation
            }
        }
        currentState = .terminated
    }

    func suspendNextShutdown() {
        shouldSuspendShutdown = true
    }

    func waitUntilShutdownEntered() async {
        guard !shutdownEntered else {
            return
        }
        await withCheckedContinuation { continuation in
            shutdownEnteredWaiter = continuation
        }
    }

    func resumeShutdown() {
        shutdownResumeWaiter?.resume()
        shutdownResumeWaiter = nil
    }

    func setState(_ state: PocketRootRuntimeState) {
        currentState = state
    }
}

@available(macOS 13.0, *)
private actor RefreshRaceLinuxRuntime: LinuxRuntime {
    private var currentState: PocketRootRuntimeState = .idle
    private var suspendedStateReadsRemaining = 0
    private var nextStateReadID = 0
    private var suspendedStateReadIDs: Set<Int> = []
    private var stateReadStartedContinuations: [
        Int: CheckedContinuation<Void, Never>
    ] = [:]
    private var stateReadContinuations: [
        Int: CheckedContinuation<Void, Never>
    ] = [:]
    private var shutdownIsSuspended = false
    private var shutdownStartedContinuation: CheckedContinuation<Void, Never>?
    private var shutdownContinuation: CheckedContinuation<Void, Never>?

    var state: PocketRootRuntimeState {
        get async {
            let snapshot = currentState
            guard suspendedStateReadsRemaining > 0 else {
                return snapshot
            }
            suspendedStateReadsRemaining -= 1
            let stateReadID = nextStateReadID
            nextStateReadID += 1
            suspendedStateReadIDs.insert(stateReadID)
            stateReadStartedContinuations.removeValue(forKey: stateReadID)?.resume()
            await withCheckedContinuation { continuation in
                stateReadContinuations[stateReadID] = continuation
            }
            return snapshot
        }
    }

    func boot(configuration: PocketRootConfiguration) async throws {
        currentState = .ready
    }

    func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult {
        throw PocketRootError.unsupportedOperation("Not used by this test.")
    }

    func makeSession(
        configuration: PocketRootSessionConfiguration
    ) async throws -> any PocketRootSession {
        throw PocketRootError.unsupportedOperation("Not used by this test.")
    }

    func shutdown() async throws {
        currentState = .shuttingDown
        shutdownIsSuspended = true
        shutdownStartedContinuation?.resume()
        shutdownStartedContinuation = nil
        await withCheckedContinuation { continuation in
            shutdownContinuation = continuation
        }
        currentState = .terminated
    }

    func suspendNextStateReads(_ count: Int) {
        suspendedStateReadsRemaining = count
    }

    func waitForStateReadToSuspend(_ stateReadID: Int) async {
        guard !suspendedStateReadIDs.contains(stateReadID) else {
            return
        }
        await withCheckedContinuation { continuation in
            stateReadStartedContinuations[stateReadID] = continuation
        }
    }

    func resumeStateRead(_ stateReadID: Int) {
        stateReadContinuations.removeValue(forKey: stateReadID)?.resume()
    }

    func setState(_ state: PocketRootRuntimeState) {
        currentState = state
    }

    func waitForShutdownToSuspend() async {
        guard !shutdownIsSuspended else {
            return
        }
        await withCheckedContinuation { continuation in
            shutdownStartedContinuation = continuation
        }
    }

    func resumeShutdown() {
        shutdownContinuation?.resume()
        shutdownContinuation = nil
    }
}
