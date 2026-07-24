import Darwin
import Foundation
import PocketRootCore
import PocketRootIshRuntimeIntegration
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

private enum PocketRootRuntimeSmokeRunner {
    static let archiveFileName = "pocketroot-fs-v0.3.3.tar.gz"
    static let reportFileName = "pocketroot-smoke-result.json"
    static let progressFileName = "pocketroot-smoke-progress.txt"
    static let sustainedOutputByteCount = 8 * 1_024 * 1_024
    static let maximumStandardErrorBytes = 64
    static let maximumPeakResidentBytes: UInt64 = 256 * 1_024 * 1_024

    static func run(environment: PocketRootSmokeEnvironment) async -> PocketRootSmokeReport {
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
            let applicationSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("PocketRootSmoke", isDirectory: true)
            try fileManager.createDirectory(
                at: applicationSupportURL,
                withIntermediateDirectories: true
            )
            let archiveURL = documentsURL.appendingPathComponent(archiveFileName)

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
                    command: "sleep 2",
                    workingDirectory: "/",
                    timeout: .milliseconds(100)
                )
            )
            try require(timedOut.timedOut, "Timeout was not reported.")
            checks.append(PocketRootSmokeCheck(name: "timeout", detail: "100 ms"))

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

            // v0.4.0-abi.4 must return after soft-halting and joining the
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
            let report = await PocketRootRuntimeSmokeRunner.run(environment: environment)
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
}
