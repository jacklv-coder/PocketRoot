import Foundation
import PocketRootCore

@available(macOS 13.0, *)
package actor IshLinuxRuntime: LinuxRuntime {
    private let ownerID = UUID()
    private let configuration: PocketRootIshRuntimeConfiguration
    private let driver: any IshRuntimeDriver
    private let executor: BlockingIshExecutor
    private let processGate: IshProcessGate
    private let rootFSValidator: @Sendable (URL) throws -> Void
    private var ownsProcess = false
    private var commandInFlight = false
    private var runtimeState: PocketRootRuntimeState = .idle

    package init(configuration: PocketRootIshRuntimeConfiguration) {
        self.init(
            configuration: configuration,
            driver: makeDefaultIshRuntimeDriver(),
            executor: .shared,
            processGate: .shared,
            rootFSValidator: { try IshLinuxRuntime.validateRootFS($0) }
        )
    }

    init(
        configuration: PocketRootIshRuntimeConfiguration,
        driver: any IshRuntimeDriver,
        executor: BlockingIshExecutor = BlockingIshExecutor(),
        processGate: IshProcessGate = IshProcessGate(),
        rootFSValidator: @escaping @Sendable (URL) throws -> Void = {
            try IshLinuxRuntime.validateRootFS($0)
        }
    ) {
        self.configuration = configuration
        self.driver = driver
        self.executor = executor
        self.processGate = processGate
        self.rootFSValidator = rootFSValidator
    }

    package var state: PocketRootRuntimeState {
        runtimeState
    }

    package func boot(configuration _: PocketRootConfiguration) async throws {
        switch runtimeState {
        case .idle:
            break
        case .terminated:
            throw PocketRootError.restartRequired
        case .ready:
            throw PocketRootError.runtimeFailure("Linux Runtime is already booted.")
        case .failed:
            // Re-enter the process gate so a failed non-owner can report the
            // current global state and a failed owner receives restartRequired.
            break
        default:
            throw PocketRootError.runtimeFailure(
                "Linux Runtime cannot boot from its current state."
            )
        }

        do {
            try rootFSValidator(configuration.rootFSURL)
        } catch let error as PocketRootError {
            throw error
        } catch {
            throw PocketRootError.rootFSUnavailable(
                "Unable to validate the fakefs at \(configuration.rootFSURL.path): "
                    + error.localizedDescription
            )
        }
        do {
            try IshRuntimeHealthCheck.validateConfiguration(
                configuration.healthCheck,
                workingDirectory: configuration.workDirectory
            )
        } catch {
            throw map(error)
        }
        if let supervisorGuestPath = configuration.supervisorGuestPath,
           supervisorGuestPath.contains("\0")
        {
            throw PocketRootError.runtimeFailure(
                "Invalid runtime configuration: supervisor guest path must not contain a NUL byte."
            )
        }
        // Close the actor-reentrancy window before the first suspension.
        runtimeState = .booting

        let options = IshDriverBootOptions(
            rootFSPath: configuration.rootFSURL.path,
            workDirectory: configuration.workDirectory,
            supervisorGuestPath: configuration.supervisorGuestPath,
            kernelLogFileDescriptor: configuration.kernelLogFileDescriptor
        )
        let healthConfiguration = configuration.healthCheck
        let healthWorkingDirectory = configuration.workDirectory
        let healthRequest = IshRuntimeHealthCheck.makeRequest(
            configuration: healthConfiguration,
            workingDirectory: healthWorkingDirectory
        )

        do {
            try await processGate.claim(for: ownerID)
            ownsProcess = true
            try await executor.perform { [driver] in
                try driver.boot(options)
                let healthResult = try driver.execute(healthRequest)
                try IshRuntimeHealthCheck.validate(
                    healthResult,
                    configuration: healthConfiguration,
                    workingDirectory: healthWorkingDirectory
                )
            }
            runtimeState = .ready
        } catch {
            if ownsProcess {
                await processGate.markTerminated(for: ownerID)
            }
            runtimeState = .failed(error.localizedDescription)
            throw map(error)
        }
    }

    package func execute(
        _ request: PocketRootCommandRequest
    ) async throws -> PocketRootCommandResult {
        switch runtimeState {
        case .ready:
            break
        case .terminated:
            throw PocketRootError.restartRequired
        default:
            throw PocketRootError.runtimeNotBooted
        }

        let requestedTimeout = request.timeout.timeInterval
        guard requestedTimeout > 0, requestedTimeout <= 86_400 else {
            throw PocketRootError.invalidCommandRequest(
                "timeout must be greater than zero and no longer than 24 hours."
            )
        }
        // IshEmbed converts sub-millisecond intervals to timeout_ms == 0,
        // which means no timeout. Clamp valid tiny durations to one ms.
        let nativeTimeout = max(requestedTimeout, 0.001)
        guard configuration.maximumStandardOutputBytes > 0,
              configuration.maximumStandardErrorBytes > 0
        else {
            throw PocketRootError.invalidCommandRequest(
                "runtime output limits must be greater than zero."
            )
        }
        guard !request.command.contains("\0") else {
            throw PocketRootError.invalidCommandRequest(
                "command must not contain a NUL byte."
            )
        }
        guard !request.workingDirectory.contains("\0") else {
            throw PocketRootError.invalidCommandRequest(
                "working directory must not contain a NUL byte."
            )
        }
        guard request.environment.allSatisfy({ key, value in
            !key.isEmpty && !key.contains("=") && !key.contains("\0")
                && !value.contains("\0")
        }) else {
            throw PocketRootError.invalidCommandRequest(
                "environment keys must be nonempty and contain neither '=' nor NUL; "
                    + "environment values must not contain NUL."
            )
        }

        guard !commandInFlight else {
            throw PocketRootError.runtimeFailure(
                "PocketRoot currently permits one one-shot command at a time."
            )
        }
        commandInFlight = true
        defer {
            commandInFlight = false
        }

        try await processGate.requireOwnership(for: ownerID)

        let driverRequest = IshDriverCommandRequest(
            arguments: ["/bin/sh", "-lc", request.command],
            workingDirectory: request.workingDirectory,
            environment: request.environment.isEmpty ? nil : request.environment,
            timeout: nativeTimeout,
            mergeStandardError: request.mergeStandardError,
            maximumStandardOutputBytes: configuration.maximumStandardOutputBytes,
            maximumStandardErrorBytes: configuration.maximumStandardErrorBytes
        )

        do {
            let result = try await executor.perform { [driver] in
                try driver.execute(driverRequest)
            }
            return PocketRootCommandResult(
                exitCode: result.exitCode,
                signal: result.signal,
                standardOutput: result.standardOutput,
                standardError: result.standardError,
                timedOut: result.timedOut
            )
        } catch {
            if let driverError = error as? IshRuntimeDriverError,
               driverError.requiresRuntimeRestart
            {
                await processGate.markTerminated(for: ownerID)
                runtimeState = .failed(error.localizedDescription)
            }
            throw map(error)
        }
    }

    package func makeSession(
        configuration: PocketRootSessionConfiguration
    ) async throws -> any PocketRootSession {
        throw PocketRootError.unsupportedOperation(
            "Interactive IshEmbed sessions are planned after the one-shot command gate."
        )
    }

    package func shutdown() async throws {
        switch runtimeState {
        case .idle, .terminated:
            return
        case .failed:
            if ownsProcess {
                throw PocketRootError.restartRequired
            }
            return
        case .ready:
            break
        case .preparingRootFS, .booting, .shuttingDown:
            throw PocketRootError.runtimeFailure(
                "Linux Runtime cannot shut down from its current state."
            )
        }

        guard !commandInFlight else {
            throw PocketRootError.runtimeFailure(
                "Wait for the active one-shot command to finish before shutting down."
            )
        }
        // Close the lifecycle before awaiting the process gate or native queue.
        runtimeState = .shuttingDown

        do {
            try await processGate.requireOwnership(for: ownerID)
            // v0.4.0-abi.3 returns after supervisor exit, kernel soft-halt, and
            // a bounded pthread join. The process-global runtime remains
            // single-lifecycle, so successful shutdown is terminal.
            try await executor.perform { [driver] in
                try driver.shutdown()
            }
            await processGate.markTerminated(for: ownerID)
            runtimeState = .terminated
        } catch {
            await processGate.markTerminated(for: ownerID)
            runtimeState = .failed(error.localizedDescription)
            throw map(error)
        }
    }

    private static func validateRootFS(_ rootFSURL: URL) throws {
        var isDirectory: ObjCBool = false
        let path = rootFSURL.path
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw PocketRootError.rootFSUnavailable(
                "Expected a materialized fakefs directory at \(path)."
            )
        }
        let rootValues = try rootFSURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw PocketRootError.rootFSUnavailable(
                "The fakefs root must be a real directory rather than a symbolic link."
            )
        }

        let metadataURL = rootFSURL.appendingPathComponent("meta.db")
        let metadataPath = metadataURL.path
        let dataURL = rootFSURL
            .appendingPathComponent("data", isDirectory: true)
        let dataPath = dataURL.path
        var dataIsDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: metadataPath),
              FileManager.default.fileExists(atPath: dataPath, isDirectory: &dataIsDirectory),
              dataIsDirectory.boolValue
        else {
            throw PocketRootError.rootFSUnavailable(
                "The fakefs must contain meta.db and a data directory."
            )
        }

        let metadataValues = try metadataURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        let dataValues = try dataURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard metadataValues.isRegularFile == true,
              metadataValues.isSymbolicLink != true,
              dataValues.isDirectory == true,
              dataValues.isSymbolicLink != true
        else {
            throw PocketRootError.rootFSUnavailable(
                "meta.db must be a real regular file and data must be a real directory."
            )
        }
    }

    private func map(_ error: Error) -> PocketRootError {
        if let error = error as? PocketRootError {
            return error
        }
        if case let IshRuntimeDriverError.outputLimitExceeded(stream, limit) = error {
            return .commandOutputLimitExceeded(stream: stream, limit: limit)
        }
        if let description = (error as? LocalizedError)?.errorDescription {
            return .runtimeFailure(description)
        }
        return .runtimeFailure(String(describing: error))
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let value = components
        let seconds = Double(value.seconds)
        let fractionalSeconds = Double(value.attoseconds) / 1_000_000_000_000_000_000
        return max(0, seconds + fractionalSeconds)
    }
}
