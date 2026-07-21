import Foundation
import PocketRootCore
import PocketRootIshRuntimeIntegration
import UIKit

private struct PocketRootSmokeCheck: Codable, Sendable {
    let name: String
    let detail: String
}

private struct PocketRootSmokeReport: Codable, Sendable {
    let success: Bool
    let checks: [PocketRootSmokeCheck]
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

    static func run() async -> PocketRootSmokeReport {
        let startedAt = Date()
        var checks: [PocketRootSmokeCheck] = []
        var system: PocketRootSystem?

        do {
            let fileManager = FileManager.default
            try require(
                UIDevice.current.systemVersion.hasPrefix("18."),
                "Smoke must run on iOS 18, not \(UIDevice.current.systemVersion)."
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
            let archiveURL = documentsURL.appendingPathComponent(archiveFileName)

            let prepared = try await PocketRootIshSystemFactory.prepareSystem(
                archiveURL: archiveURL,
                applicationSupportURL: applicationSupportURL,
                workDirectory: "/",
                maximumStandardOutputBytes: 64,
                maximumStandardErrorBytes: 64
            )
            system = prepared.system
            checks.append(
                PocketRootSmokeCheck(
                    name: "rootfs",
                    detail: "prepared \(prepared.installation.version)"
                )
            )

            try await prepared.system.boot()
            try require(
                await prepared.system.state == .ready,
                "Runtime did not reach ready."
            )
            checks.append(PocketRootSmokeCheck(name: "boot", detail: "ready"))

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

            let environment = try await prepared.system.execute(
                PocketRootCommandRequest(
                    command: "printf '%s' \"$POCKETROOT_SMOKE\"",
                    workingDirectory: "/",
                    environment: ["POCKETROOT_SMOKE": "environment-ok"]
                )
            )
            try require(environment.stdout == "environment-ok", "Environment was not applied.")
            checks.append(PocketRootSmokeCheck(name: "environment", detail: environment.stdout))

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
                        command: "i=0; while [ \"$i\" -lt 256 ]; do printf x; i=$((i + 1)); done",
                        workingDirectory: "/"
                    )
                )
                throw PocketRootSmokeFailure(message: "stdout limit was not enforced.")
            } catch PocketRootError.commandOutputLimitExceeded(let stream, let limit) {
                try require(stream == "stdout", "Unexpected limited stream: \(stream)")
                try require(limit == 64, "Unexpected stdout limit: \(limit)")
                checks.append(PocketRootSmokeCheck(name: "output-limit", detail: "64 bytes"))
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
            checks.append(PocketRootSmokeCheck(name: "post-output-limit", detail: "ready"))

            // The pinned iSH kernel deliberately calls _exit(0) when PID 1
            // shuts down. Persist the successful command report before asking
            // the native runtime to terminate the host App process. The host
            // script separately verifies that this process actually exits.
            checks.append(
                PocketRootSmokeCheck(
                    name: "shutdown",
                    detail: "host-process exit requested"
                )
            )
            let preShutdownReport = PocketRootSmokeReport(
                success: true,
                checks: checks,
                error: nil,
                startedAt: startedAt,
                finishedAt: Date()
            )
            try write(preShutdownReport)
            try await prepared.system.shutdown()

            // This fallback is reachable only if a future upstream runtime
            // changes shutdown to return instead of terminating the process.
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
                checks.append(PocketRootSmokeCheck(name: "restart", detail: "required"))
            }

            return PocketRootSmokeReport(
                success: true,
                checks: checks,
                error: nil,
                startedAt: startedAt,
                finishedAt: Date()
            )
        } catch {
            let report = PocketRootSmokeReport(
                success: false,
                checks: checks,
                error: error.localizedDescription,
                startedAt: startedAt,
                finishedAt: Date()
            )
            // A native cleanup shutdown also exits the App process, so failure
            // evidence must be durable before attempting that cleanup.
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
            let report = await PocketRootRuntimeSmokeRunner.run()
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
