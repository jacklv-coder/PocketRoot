import Darwin
import Foundation
import PocketRootCore
@_spi(PocketRootRuntimeSmoke) import PocketRootIshRuntimeIntegration
import PocketRootResources
import UIKit

private struct PocketRootSmokeCheck: Codable, Sendable {
    let name: String
    let detail: String
}

private struct PocketRootSmokeEnvironment: Codable, Sendable {
    let deviceFamily: String
    let systemName: String
    let systemVersion: String
}

private struct PocketRootSmokeReport: Codable, Sendable {
    let success: Bool
    let checks: [PocketRootSmokeCheck]
    let environment: PocketRootSmokeEnvironment
    let error: String?
    let startedAt: Date
    let finishedAt: Date
}

private struct PocketRootSmokeFailure: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private enum PocketRootSmokeRelaunchPersistencePhase: Sendable {
    case disabled
    case seed
    case verify
}

private enum PocketRootRuntimeSmokeRunner {
    static let archiveFileName = "pocketroot-fs-v0.3.3.tar.gz"
    static let reportFileName = "pocketroot-smoke-result.json"
    static let progressFileName = "pocketroot-smoke-progress.txt"
    static let lifecycleResumeFileName = "pocketroot-smoke-lifecycle-resume.txt"
    static let uiLifecycleFileName = "pocketroot-smoke-ui-lifecycle.txt"
    static let memoryWarningFileName = "pocketroot-smoke-memory-warning.txt"
    static let memoryWarningActiveFileName = "pocketroot-smoke-memory-warning-active.txt"
    static let memoryWarningActiveGuestPath = "/root/\(memoryWarningActiveFileName)"
    static let relaunchPersistenceFileName = "/root/pocketroot-smoke-relaunch.txt"
    static let relaunchPersistenceMarker = "pocketroot-forced-relaunch-v1"
    static let sustainedOutputByteCount = 8 * 1_024 * 1_024
    static let maximumStandardErrorBytes = 64
    static let maximumPeakResidentBytes: UInt64 = 256 * 1_024 * 1_024

    static func run(
        environment: PocketRootSmokeEnvironment,
        lifecycleMode: Bool = false,
        uiLifecycleMode: Bool = false,
        storageFailureMode: Bool = false,
        memoryWarningMode: Bool = false,
        relaunchPersistencePhase: PocketRootSmokeRelaunchPersistencePhase = .disabled
    ) async -> PocketRootSmokeReport {
        let startedAt = Date()
        var checks: [PocketRootSmokeCheck] = []
        var system: PocketRootSystem?

        do {
            let fileManager = FileManager.default
            try require(
                ProcessInfo.processInfo.isOperatingSystemAtLeast(
                    OperatingSystemVersion(majorVersion: 18, minorVersion: 0, patchVersion: 0)
                ),
                "Smoke requires iOS 18 or newer, not \(environment.systemVersion)."
            )
            let documentsURL = try requireDirectory(
                fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
                name: "Documents"
            )
            let applicationSupportBaseURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let applicationSupportURL = applicationSupportBaseURL.appendingPathComponent(
                storageFailureMode ? "PocketRootStorageFailureSmoke" : "PocketRootSmoke",
                isDirectory: true
            )
            if storageFailureMode,
               fileManager.fileExists(atPath: applicationSupportURL.path)
            {
                try fileManager.removeItem(at: applicationSupportURL)
            }
            try fileManager.createDirectory(
                at: applicationSupportURL,
                withIntermediateDirectories: true
            )
            let archiveURL = documentsURL.appendingPathComponent(archiveFileName)

            if storageFailureMode {
                checks.append(
                    contentsOf: try await runStorageFailureChecks(
                        archiveURL: archiveURL,
                        applicationSupportURL: applicationSupportURL
                    )
                )
            }

            writeProgress("preparing-rootfs")
            let prepared = try await PocketRootIshSystemFactory.prepareSystem(
                archiveURL: archiveURL,
                applicationSupportURL: applicationSupportURL,
                workDirectory: "/",
                maximumStandardOutputBytes: sustainedOutputByteCount,
                maximumStandardErrorBytes: maximumStandardErrorBytes
            )
            system = prepared.system
            checks.append(
                PocketRootSmokeCheck(
                    name: "rootfs",
                    detail: "prepared \(prepared.installation.version)"
                )
            )

            writeProgress("booting")
            try await prepared.system.boot()
            try require(
                await prepared.system.state == .ready,
                "Runtime did not reach ready."
            )
            checks.append(PocketRootSmokeCheck(name: "boot", detail: "ready"))

            switch relaunchPersistencePhase {
            case .disabled:
                break
            case .seed:
                let seed = try await prepared.system.execute(
                    PocketRootCommandRequest(
                        command: "printf '%s' '\(relaunchPersistenceMarker)' "
                            + "> \(relaunchPersistenceFileName) && sync",
                        workingDirectory: "/"
                    )
                )
                try require(seed.exitCode == 0, "Unable to seed the relaunch marker.")
                let seededMarker = try await prepared.system.execute(
                    PocketRootCommandRequest(
                        command: "cat \(relaunchPersistenceFileName)",
                        workingDirectory: "/"
                    )
                )
                try require(
                    seededMarker.exitCode == 0
                        && seededMarker.stdout == relaunchPersistenceMarker,
                    "The relaunch marker was not readable before host termination."
                )
                writeProgress("awaiting-host-termination")
                try await awaitHostForcedTermination()
            case .verify:
                try require(
                    prepared.installation.reusedExistingInstallation,
                    "The relaunched App did not reuse the existing RootFS installation."
                )
                let persistedMarker = try await prepared.system.execute(
                    PocketRootCommandRequest(
                        command: "cat \(relaunchPersistenceFileName)",
                        workingDirectory: "/"
                    )
                )
                try require(
                    persistedMarker.exitCode == 0
                        && persistedMarker.stdout == relaunchPersistenceMarker,
                    "The guest marker did not survive forced App termination."
                )
                let cleanup = try await prepared.system.execute(
                    PocketRootCommandRequest(
                        command: "rm -f \(relaunchPersistenceFileName) && sync "
                            + "&& test ! -e \(relaunchPersistenceFileName)",
                        workingDirectory: "/"
                    )
                )
                try require(cleanup.exitCode == 0, "Unable to clean the relaunch marker.")
                checks.append(
                    PocketRootSmokeCheck(
                        name: "forced-relaunch-persistence",
                        detail: "new process reused RootFS and recovered guest data"
                    )
                )
            }

            writeProgress("running-command-checks")
            let architecture = try await prepared.system.execute(
                PocketRootCommandRequest(command: "/bin/uname -m", workingDirectory: "/")
            )
            try require(architecture.exitCode == 0, "uname exited \(architecture.exitCode).")
            try require(trimmed(architecture.stdout) == "aarch64", "Unexpected guest architecture.")
            checks.append(PocketRootSmokeCheck(name: "uname", detail: "aarch64"))

            let alpine = try await prepared.system.execute(
                PocketRootCommandRequest(
                    command: "cat /etc/alpine-release",
                    workingDirectory: "/"
                )
            )
            let alpineVersion = trimmed(alpine.stdout)
            try require(alpine.exitCode == 0, "Alpine version command failed.")
            try require(alpineVersion == "3.19.1", "Unexpected Alpine version: \(alpineVersion)")
            checks.append(PocketRootSmokeCheck(name: "alpine", detail: alpineVersion))

            let workingDirectory = try await prepared.system.execute(
                PocketRootCommandRequest(command: "pwd", workingDirectory: "/")
            )
            try require(trimmed(workingDirectory.stdout) == "/", "Working directory was not applied.")
            checks.append(PocketRootSmokeCheck(name: "cwd", detail: "/"))

            let guestEnvironment = try await prepared.system.execute(
                PocketRootCommandRequest(
                    command: "printf '%s' \"$POCKETROOT_SMOKE\"",
                    workingDirectory: "/",
                    environment: ["POCKETROOT_SMOKE": "environment-ok"]
                )
            )
            try require(guestEnvironment.stdout == "environment-ok", "Environment was not applied.")
            checks.append(PocketRootSmokeCheck(name: "environment", detail: guestEnvironment.stdout))

            let streams = try await prepared.system.execute(
                PocketRootCommandRequest(
                    command: "printf 'stdout-ok'; printf 'stderr-ok' >&2; exit 7",
                    workingDirectory: "/"
                )
            )
            try require(streams.exitCode == 7, "Exit status was not preserved.")
            try require(streams.stdout == "stdout-ok", "stdout was not preserved.")
            try require(streams.stderr == "stderr-ok", "stderr was not preserved.")
            checks.append(PocketRootSmokeCheck(name: "streams", detail: "exit 7, split"))

            let merged = try await prepared.system.execute(
                PocketRootCommandRequest(
                    command: "printf 'merged-ok' >&2",
                    workingDirectory: "/",
                    mergeStandardError: true
                )
            )
            try require(merged.stdout == "merged-ok", "Merged stderr did not reach stdout.")
            try require(merged.standardError.isEmpty, "Merged stderr was also returned separately.")
            checks.append(PocketRootSmokeCheck(name: "stderr-merge", detail: "merged"))

            writeProgress("running-sustained-output-check")
            do {
                let sustainedOutput = try await prepared.system.execute(
                    PocketRootCommandRequest(
                        command: "/bin/dd if=/dev/zero bs=65536 count=128 2>/dev/null",
                        workingDirectory: "/",
                        timeout: .seconds(60)
                    )
                )
                try require(
                    sustainedOutput.exitCode == 0,
                    "Sustained output command exited \(sustainedOutput.exitCode)."
                )
                try require(
                    sustainedOutput.standardOutput.count == sustainedOutputByteCount,
                    "Sustained output returned "
                        + "\(sustainedOutput.standardOutput.count) bytes."
                )
                try require(
                    sustainedOutput.standardOutput.allSatisfy { $0 == 0 },
                    "Sustained binary output was corrupted."
                )
                try require(
                    sustainedOutput.standardError.isEmpty,
                    "Sustained output unexpectedly wrote stderr."
                )
            }
            checks.append(
                PocketRootSmokeCheck(
                    name: "sustained-output",
                    detail: "8 MiB binary stdout, byte-exact"
                )
            )

            let timedOut = try await prepared.system.execute(
                PocketRootCommandRequest(
                    command: "printf 'before-timeout'; sleep 2",
                    workingDirectory: "/",
                    timeout: .milliseconds(100)
                )
            )
            try require(timedOut.timedOut, "Timeout was not reported.")
            try require(
                timedOut.stdout == "before-timeout",
                "Partial stdout was not preserved across timeout cleanup."
            )
            checks.append(
                PocketRootSmokeCheck(
                    name: "timeout",
                    detail: "100 ms, partial stdout preserved"
                )
            )

            let afterTimeout = try await prepared.system.execute(
                PocketRootCommandRequest(
                    command: "printf 'after-timeout-ok'",
                    workingDirectory: "/"
                )
            )
            try require(afterTimeout.stdout == "after-timeout-ok", "Runtime did not recover after timeout.")
            checks.append(PocketRootSmokeCheck(name: "post-timeout", detail: "ready"))

            do {
                _ = try await prepared.system.execute(
                    PocketRootCommandRequest(
                        command: "/bin/dd if=/dev/zero bs=65536 count=129 2>/dev/null",
                        workingDirectory: "/",
                        timeout: .seconds(60)
                    )
                )
                throw PocketRootSmokeFailure(message: "stdout limit was not enforced.")
            } catch PocketRootError.commandOutputLimitExceeded(let stream, let limit) {
                try require(stream == "stdout", "Unexpected limited stream: \(stream)")
                try require(
                    limit == sustainedOutputByteCount,
                    "Unexpected stdout limit: \(limit)"
                )
                checks.append(
                    PocketRootSmokeCheck(
                        name: "stdout-output-limit",
                        detail: "8 MiB"
                    )
                )
            }

            do {
                _ = try await prepared.system.execute(
                    PocketRootCommandRequest(
                        command: "i=0; while [ \"$i\" -lt 256 ]; do "
                            + "printf x >&2; i=$((i + 1)); done",
                        workingDirectory: "/"
                    )
                )
                throw PocketRootSmokeFailure(message: "stderr limit was not enforced.")
            } catch PocketRootError.commandOutputLimitExceeded(let stream, let limit) {
                try require(stream == "stderr", "Unexpected limited stream: \(stream)")
                try require(
                    limit == maximumStandardErrorBytes,
                    "Unexpected stderr limit: \(limit)"
                )
                checks.append(
                    PocketRootSmokeCheck(
                        name: "stderr-output-limit",
                        detail: "stderr, 64 bytes"
                    )
                )
            }

            let afterOutputLimit = try await prepared.system.execute(
                PocketRootCommandRequest(
                    command: "printf 'after-limit-ok'",
                    workingDirectory: "/"
                )
            )
            try require(
                afterOutputLimit.stdout == "after-limit-ok",
                "Runtime did not recover after output-limit termination."
            )
            checks.append(PocketRootSmokeCheck(name: "post-output-limits", detail: "ready"))

            writeProgress("running-cancellation-check")
            let cancellationCommand = Task {
                try await prepared.system.execute(
                    PocketRootCommandRequest(
                        command: "exec sleep 30",
                        workingDirectory: "/",
                        timeout: .seconds(60)
                    )
                )
            }
            await Task.yield()
            try await Task.sleep(for: .milliseconds(500))
            let cancellationClock = ContinuousClock()
            let cancellationStartedAt = cancellationClock.now
            cancellationCommand.cancel()
            do {
                _ = try await cancellationCommand.value
                throw PocketRootSmokeFailure(
                    message: "A cancelled native command returned success."
                )
            } catch is CancellationError {
                // Success means the native driver terminated and reaped the
                // guest command before propagating Swift Task cancellation.
            }
            let cancellationDuration = cancellationStartedAt.duration(
                to: cancellationClock.now
            )
            try require(
                cancellationDuration < .seconds(7),
                "Native cancellation exceeded seven seconds: \(cancellationDuration)."
            )
            try require(
                await prepared.system.state == .ready,
                "Runtime was not ready after command cancellation."
            )
            let afterCancellation = try await prepared.system.execute(
                PocketRootCommandRequest(
                    command: "printf 'after-cancellation-ok'",
                    workingDirectory: "/"
                )
            )
            try require(
                afterCancellation.stdout == "after-cancellation-ok",
                "Runtime did not recover after command cancellation."
            )
            checks.append(
                PocketRootSmokeCheck(
                    name: "cancellation",
                    detail: "native termination confirmed, runtime ready"
                )
            )

            if memoryWarningMode {
                checks.append(
                    try await runMemoryWarningRecoveryCheck(
                        system: prepared.system,
                        documentsURL: documentsURL,
                        rootFSURL: prepared.installation.rootFSURL
                    )
                )
            }

            if lifecycleMode {
                try await awaitHostSuspendResume(in: documentsURL)
                let afterSuspendResume = try await prepared.system.execute(
                    PocketRootCommandRequest(
                        command: "printf 'after-suspend-resume-ok'",
                        workingDirectory: "/"
                    )
                )
                try require(
                    afterSuspendResume.stdout == "after-suspend-resume-ok",
                    "Runtime did not execute after process suspend/resume."
                )
                try require(
                    await prepared.system.state == .ready,
                    "Runtime was not ready after process suspend/resume."
                )
                checks.append(
                    PocketRootSmokeCheck(
                        name: "process-suspend-resume",
                        detail: "host resumed, runtime ready, guest command passed"
                    )
                )
            }

            if uiLifecycleMode {
                try await awaitHostUIKitLifecycle(in: documentsURL)
                let afterUIKitLifecycle = try await prepared.system.execute(
                    PocketRootCommandRequest(
                        command: "printf 'after-ui-lifecycle-ok'",
                        workingDirectory: "/"
                    )
                )
                try require(
                    afterUIKitLifecycle.stdout == "after-ui-lifecycle-ok",
                    "Runtime did not execute after the UIKit lifecycle transition."
                )
                try require(
                    await prepared.system.state == .ready,
                    "Runtime was not ready after the UIKit lifecycle transition."
                )
                checks.append(
                    PocketRootSmokeCheck(
                        name: "ui-background-foreground",
                        detail: "background, foreground, active, runtime ready"
                    )
                )
            }

            // v0.4.0-abi.6 must return after soft-halting and joining the
            // embedded kernel. Do not persist success until both the terminal
            // state and the no-reboot contract have been observed.
            writeProgress("shutting-down")
            try await prepared.system.shutdown()

            try require(
                await prepared.system.state == .terminated,
                "Shutdown did not produce the terminal state."
            )

            do {
                _ = try await prepared.system.execute(
                    PocketRootCommandRequest(command: "true", workingDirectory: "/")
                )
                throw PocketRootSmokeFailure(message: "A terminated runtime executed a command.")
            } catch PocketRootError.restartRequired {
                checks.append(
                    PocketRootSmokeCheck(
                        name: "shutdown",
                        detail: "returned, terminated, restart required"
                    )
                )
            }

            let peakResidentBytes = try peakResidentByteCount()
            try require(
                peakResidentBytes <= maximumPeakResidentBytes,
                "Peak resident memory exceeded \(formatMebibytes(maximumPeakResidentBytes)): "
                    + "\(formatMebibytes(peakResidentBytes))."
            )
            checks.append(
                PocketRootSmokeCheck(
                    name: "peak-memory",
                    detail: "lifecycle peak \(formatMebibytes(peakResidentBytes)), "
                        + "limit \(formatMebibytes(maximumPeakResidentBytes))"
                )
            )

            writeProgress("completed")
            return PocketRootSmokeReport(
                success: true,
                checks: checks,
                environment: environment,
                error: nil,
                startedAt: startedAt,
                finishedAt: Date()
            )
        } catch {
            let report = PocketRootSmokeReport(
                success: false,
                checks: checks,
                environment: environment,
                error: error.localizedDescription,
                startedAt: startedAt,
                finishedAt: Date()
            )
            // Persist failure evidence before best-effort native cleanup.
            try? write(report)
            if let system {
                try? await system.shutdown()
            }
            return report
        }
    }

    static func write(_ report: PocketRootSmokeReport) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: try reportURL(), options: .atomic)
    }

    static func reportURL() throws -> URL {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw PocketRootSmokeFailure(message: "Documents directory is unavailable.")
        }
        return documentsURL.appendingPathComponent(reportFileName)
    }

    static func writeProgress(_ stage: String) {
        NSLog("PocketRoot native smoke progress: %@", stage)
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return
        }
        let progressURL = documentsURL.appendingPathComponent(progressFileName)
        try? Data(stage.utf8).write(to: progressURL, options: .atomic)
    }

    static func recordUIKitLifecycleEvent(_ event: String) {
        guard ProcessInfo.processInfo.environment["POCKETROOT_SMOKE_UI_LIFECYCLE"] == "1",
              let documentsURL = FileManager.default.urls(
                  for: .documentDirectory,
                  in: .userDomainMask
              ).first else {
            return
        }
        let eventURL = documentsURL.appendingPathComponent(uiLifecycleFileName)
        var events = (try? Data(contentsOf: eventURL)) ?? Data()
        events.append(Data("\(event)\n".utf8))
        try? events.write(to: eventURL, options: .atomic)
        writeProgress("host-\(event)")
    }

    static func recordMemoryWarningCallback() {
        guard ProcessInfo.processInfo.environment["POCKETROOT_SMOKE_MEMORY_WARNING"] == "1",
              let documentsURL = FileManager.default.urls(
                  for: .documentDirectory,
                  in: .userDomainMask
              ).first else {
            return
        }
        let eventURL = documentsURL.appendingPathComponent(memoryWarningFileName)
        try? Data("received\n".utf8).write(to: eventURL, options: .atomic)
        writeProgress("memory-warning-received")
    }

    private static func runMemoryWarningRecoveryCheck(
        system: PocketRootSystem,
        documentsURL: URL,
        rootFSURL: URL
    ) async throws -> PocketRootSmokeCheck {
        let eventURL = documentsURL.appendingPathComponent(memoryWarningFileName)
        let activeURL = rootFSURL
            .appendingPathComponent("data/root", isDirectory: true)
            .appendingPathComponent(memoryWarningActiveFileName)
        try? FileManager.default.removeItem(at: eventURL)
        try? FileManager.default.removeItem(at: activeURL)
        writeProgress("injecting-memory-warning")

        async let activeCommand = system.execute(
            PocketRootCommandRequest(
                command: "trap 'rm -f \(memoryWarningActiveGuestPath)' EXIT; "
                    + "printf 'started\\n' > \(memoryWarningActiveGuestPath) && sync "
                    + "&& printf 'before-warning' && sleep 2 && printf 'after-warning'",
                workingDirectory: "/",
                timeout: .seconds(10)
            )
        )
        try await awaitMemoryWarningCommandStart(at: activeURL)
        let callbackDelivered = await deliverMemoryWarningCallback()
        try require(callbackDelivered, "The App delegate did not expose a memory-warning callback.")
        try require(
            (try? Data(contentsOf: eventURL)) == Data("received\n".utf8),
            "The injected memory-warning callback did not persist fresh evidence."
        )

        let activeResult = try await activeCommand
        try require(
            activeResult.exitCode == 0
                && activeResult.stdout == "before-warningafter-warning",
            "The active guest command did not survive the memory-warning callback."
        )
        let afterWarning = try await system.execute(
            PocketRootCommandRequest(
                command: "printf 'after-memory-warning-ok'",
                workingDirectory: "/"
            )
        )
        try require(
            afterWarning.stdout == "after-memory-warning-ok",
            "Runtime did not execute after the memory-warning callback."
        )
        try require(
            await system.state == .ready,
            "Runtime was not ready after the memory-warning callback."
        )
        return PocketRootSmokeCheck(
            name: "memory-warning-recovery",
            detail: "start-acknowledged active command, delegate callback, and later command passed"
        )
    }

    private static func awaitMemoryWarningCommandStart(at activeURL: URL) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        let expectedMarker = Data("started\n".utf8)
        while clock.now < deadline {
            if let marker = try? Data(contentsOf: activeURL),
               marker == expectedMarker {
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw PocketRootSmokeFailure(
            message: "The guest command did not acknowledge active execution before the callback."
        )
    }

    @MainActor
    private static func deliverMemoryWarningCallback() -> Bool {
        guard let delegate = UIApplication.shared.delegate,
              delegate.responds(
                  to: #selector(UIApplicationDelegate.applicationDidReceiveMemoryWarning(_:))
              ) else {
            return false
        }
        delegate.applicationDidReceiveMemoryWarning?(UIApplication.shared)
        return true
    }

    private static func awaitHostSuspendResume(in documentsURL: URL) async throws {
        let fileManager = FileManager.default
        let resumeURL = documentsURL.appendingPathComponent(lifecycleResumeFileName)
        try? fileManager.removeItem(at: resumeURL)
        writeProgress("awaiting-host-suspend")

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(60))
        let expectedMarker = Data("resume\n".utf8)
        while clock.now < deadline {
            if let marker = try? Data(contentsOf: resumeURL),
               marker == expectedMarker {
                writeProgress("host-resumed")
                return
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw PocketRootSmokeFailure(
            message: "Host did not complete process suspend/resume within 60 seconds."
        )
    }

    private static func awaitHostUIKitLifecycle(in documentsURL: URL) async throws {
        let fileManager = FileManager.default
        let eventURL = documentsURL.appendingPathComponent(uiLifecycleFileName)
        if fileManager.fileExists(atPath: eventURL.path) {
            try fileManager.removeItem(at: eventURL)
        }
        writeProgress("awaiting-host-background")

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(60))
        let expectedEvents = Data("backgrounded\nforegrounded\nactive\n".utf8)
        while clock.now < deadline {
            if let events = try? Data(contentsOf: eventURL),
               events == expectedEvents {
                return
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw PocketRootSmokeFailure(
            message: "UIKit did not complete background, foreground, and active callbacks."
        )
    }

    private static func awaitHostForcedTermination() async throws {
        try await Task.sleep(for: .seconds(60))
        throw PocketRootSmokeFailure(
            message: "Host did not forcibly terminate the seed process within 60 seconds."
        )
    }

    private static func runStorageFailureChecks(
        archiveURL: URL,
        applicationSupportURL: URL
    ) async throws -> [PocketRootSmokeCheck] {
        var checks: [PocketRootSmokeCheck] = []

        writeProgress("testing-storage-capacity-preflight")
        do {
            _ = try await PocketRootIshSystemFactory.prepareSystemForFailureInjection(
                archiveURL: archiveURL,
                applicationSupportURL: applicationSupportURL,
                failureInjection: .insufficientStorage
            )
            throw PocketRootSmokeFailure(
                message: "The zero-capacity preflight unexpectedly installed a RootFS."
            )
        } catch PocketRootRootFSInstallationError.insufficientStorage(
            let requiredBytes,
            let availableBytes
        ) {
            try require(requiredBytes > 0, "Storage preflight reported no required bytes.")
            try require(availableBytes == 0, "Storage preflight ignored injected capacity.")
        }
        try requireCleanStorageFailureWorkspace(at: applicationSupportURL)
        checks.append(
            PocketRootSmokeCheck(
                name: "storage-capacity-preflight",
                detail: "zero available bytes rejected before staging"
            )
        )

        writeProgress("testing-storage-enospc-cleanup")
        do {
            _ = try await PocketRootIshSystemFactory.prepareSystemForFailureInjection(
                archiveURL: archiveURL,
                applicationSupportURL: applicationSupportURL,
                failureInjection: .gzipENOSPC
            )
            throw PocketRootSmokeFailure(
                message: "The gzip ENOSPC injection unexpectedly installed a RootFS."
            )
        } catch PocketRootArchiveExtractionError.gzipDecompressionFailed(let message) {
            try require(
                message.localizedCaseInsensitiveContains("space"),
                "Unexpected gzip ENOSPC error: \(message)"
            )
        }
        try requireCleanStorageFailureWorkspace(at: applicationSupportURL)
        checks.append(
            PocketRootSmokeCheck(
                name: "storage-enospc-cleanup",
                detail: "one-byte gzip output failed and staging was removed"
            )
        )

        writeProgress("recovering-after-storage-failures")
        return checks
    }

    private static func requireCleanStorageFailureWorkspace(
        at applicationSupportURL: URL
    ) throws {
        let rootFSURL = applicationSupportURL.appendingPathComponent(
            "rootfs",
            isDirectory: true
        )
        let entries = try FileManager.default.contentsOfDirectory(
            at: rootFSURL,
            includingPropertiesForKeys: nil
        )
        try require(
            entries.isEmpty,
            "Storage failure left RootFS entries: \(entries.map(\.lastPathComponent))."
        )
    }

    private static func requireDirectory(_ url: URL?, name: String) throws -> URL {
        guard let url else {
            throw PocketRootSmokeFailure(message: "\(name) directory is unavailable.")
        }
        return url
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else {
            throw PocketRootSmokeFailure(message: message)
        }
    }

    private static func peakResidentByteCount() throws -> UInt64 {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else {
            throw PocketRootSmokeFailure(
                message: "Unable to read peak resident memory: "
                    + String(cString: strerror(errno))
            )
        }
        try require(usage.ru_maxrss > 0, "Peak resident memory was not reported.")
        return UInt64(usage.ru_maxrss)
    }

    private static func formatMebibytes(_ byteCount: UInt64) -> String {
        String(format: "%.1f MiB", Double(byteCount) / Double(1_024 * 1_024))
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@main
@MainActor
final class PocketRootIshRuntimeSmokeApp: UIResponder, UIApplicationDelegate {
    private var statusLabel: UILabel?
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .systemBackground
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        label.text = "PocketRoot native smoke running…"
        viewController.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor, constant: -24),
            label.centerYAnchor.constraint(equalTo: viewController.view.centerYAnchor)
        ])

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        self.window = window
        statusLabel = label

        Task {
            let environment = PocketRootSmokeEnvironment(
                deviceFamily: UIDevice.current.model,
                systemName: UIDevice.current.systemName,
                systemVersion: UIDevice.current.systemVersion
            )
            let lifecycleMode =
                ProcessInfo.processInfo.environment["POCKETROOT_SMOKE_LIFECYCLE"] == "1"
            let uiLifecycleMode =
                ProcessInfo.processInfo.environment["POCKETROOT_SMOKE_UI_LIFECYCLE"] == "1"
            let storageFailureMode =
                ProcessInfo.processInfo.environment["POCKETROOT_SMOKE_STORAGE_FAILURE"] == "1"
            let memoryWarningMode =
                ProcessInfo.processInfo.environment["POCKETROOT_SMOKE_MEMORY_WARNING"] == "1"
            let relaunchPersistencePhase: PocketRootSmokeRelaunchPersistencePhase
            switch ProcessInfo.processInfo.environment[
                "POCKETROOT_SMOKE_RELAUNCH_PERSISTENCE"
            ] {
            case "seed":
                relaunchPersistencePhase = .seed
            case "verify":
                relaunchPersistencePhase = .verify
            default:
                relaunchPersistencePhase = .disabled
            }
            let report = await PocketRootRuntimeSmokeRunner.run(
                environment: environment,
                lifecycleMode: lifecycleMode,
                uiLifecycleMode: uiLifecycleMode,
                storageFailureMode: storageFailureMode,
                memoryWarningMode: memoryWarningMode,
                relaunchPersistencePhase: relaunchPersistencePhase
            )
            do {
                try PocketRootRuntimeSmokeRunner.write(report)
                label.text = report.success
                    ? "PocketRoot native smoke passed (\(report.checks.count) checks)."
                    : "PocketRoot native smoke failed:\n\(report.error ?? "unknown error")"
            } catch {
                label.text = "Unable to write smoke report:\n\(error.localizedDescription)"
            }
        }

        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        PocketRootRuntimeSmokeRunner.recordUIKitLifecycleEvent("backgrounded")
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        PocketRootRuntimeSmokeRunner.recordUIKitLifecycleEvent("foregrounded")
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        PocketRootRuntimeSmokeRunner.recordUIKitLifecycleEvent("active")
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        PocketRootRuntimeSmokeRunner.recordMemoryWarningCallback()
    }
}
