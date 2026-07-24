#if os(iOS) && arch(arm64) && canImport(IshEmbed)
import Foundation
import IshEmbed

struct IshEmbedDriver: IshRuntimeDriver {
    // The supervisor grants SIGTERM 1.5 seconds before SIGKILL and may spend
    // up to another two seconds proving adopted descendants are gone before
    // publishing EXITED. Leave bounded scheduling margin around that protocol.
    private let terminationConfirmationTimeout: TimeInterval = 5
    func boot(_ options: IshDriverBootOptions) throws {
        try IshInstance.shared.boot(
            .init(
                rootfsPath: options.rootFSPath,
                workdir: options.workDirectory,
                supervisorGuestPath: options.supervisorGuestPath,
                kernelLogFD: options.kernelLogFileDescriptor
            )
        )
    }

    func execute(_ request: IshDriverCommandRequest) throws -> IshDriverCommandResult {
        try execute(request, cancellation: IshCommandCancellation())
    }

    func execute(
        _ request: IshDriverCommandRequest,
        cancellation: IshCommandCancellation
    ) throws -> IshDriverCommandResult {
        try cancellation.check()
        // The product deadline starts at this driver entry, before native
        // SPAWN staging/admission and stdin-close admission. ABI.6 uses a
        // finite streaming timeout to keep those control operations bounded.
        let deadline = ProcessInfo.processInfo.systemUptime + request.timeout
        let spawnTimeout = deadline - ProcessInfo.processInfo.systemUptime
        guard spawnTimeout > 0 else {
            return timedOutResult()
        }

        let session: IshSession
        do {
            session = try IshInstance.shared.spawn(
                .init(
                    argv: request.arguments,
                    cwd: request.workingDirectory,
                    env: request.environment,
                    mergeStderrIntoStdout: request.mergeStandardError,
                    timeout: spawnTimeout
                )
            )
        } catch IshError.raw(let code, _) where code == -12 {
            // ABI.6 guarantees a streaming SPAWN timeout returns without a
            // session and without publishing a late command.
            try cancellation.check()
            return timedOutResult()
        } catch IshError.raw(let code, let message) {
            if let terminalFailure = IshRuntimeTransportPolicy.terminalSpawnFailure(
                code: code,
                message: message
            ) {
                throw terminalFailure
            }
            throw IshError.raw(code, message)
        }
        defer {
            session.close()
        }
        var standardOutput = Data()
        var standardError = Data()
        var terminationConfirmed = false
        do {
            try cancellation.check()
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                let terminationOutput = try terminateAndConfirmExit(
                    session,
                    preserving: standardOutput,
                    standardError: standardError,
                    maximumStandardOutputBytes: request.maximumStandardOutputBytes,
                    maximumStandardErrorBytes: request.maximumStandardErrorBytes
                )
                terminationConfirmed = true
                if let outputLimitError = terminationOutput.outputLimitError {
                    throw outputLimitError
                }
                return timedOutResult(
                    standardOutput: terminationOutput.standardOutput,
                    standardError: terminationOutput.standardError
                )
            }
            do {
                try session.closeStdin()
            } catch IshError.raw(let code, _) where code == -12 {
                // The finite native session reuses the original SPAWN
                // deadline for stdin-close admission. It never publishes a
                // late EOF frame after that product deadline.
                try cancellation.check()
                let terminationOutput = try terminateAndConfirmExit(
                    session,
                    preserving: standardOutput,
                    standardError: standardError,
                    maximumStandardOutputBytes: request.maximumStandardOutputBytes,
                    maximumStandardErrorBytes: request.maximumStandardErrorBytes
                )
                terminationConfirmed = true
                if let outputLimitError = terminationOutput.outputLimitError {
                    throw outputLimitError
                }
                return timedOutResult(
                    standardOutput: terminationOutput.standardOutput,
                    standardError: terminationOutput.standardError
                )
            }

            while true {
                try cancellation.check()
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                guard remaining > 0 else {
                    let terminationOutput = try terminateAndConfirmExit(
                        session,
                        preserving: standardOutput,
                        standardError: standardError,
                        maximumStandardOutputBytes: request.maximumStandardOutputBytes,
                        maximumStandardErrorBytes: request.maximumStandardErrorBytes
                    )
                    terminationConfirmed = true
                    if let outputLimitError = terminationOutput.outputLimitError {
                        throw outputLimitError
                    }
                    return timedOutResult(
                        standardOutput: terminationOutput.standardOutput,
                        standardError: terminationOutput.standardError
                    )
                }

                let event: IshSessionEvent
                do {
                    event = try session.read(timeout: min(remaining, 0.25))
                } catch IshError.raw(let code, _) where code == -12 {
                    // ISH_ERR_TIMEOUT: poll again so the wall-clock deadline is
                    // enforced without an unbounded native read.
                    continue
                } catch IshError.raw(let code, let message) where code == -15 {
                    // Wire v4 surfaces supervisor ERROR as a typed terminal
                    // status rather than synthesizing an EXITED payload.
                    throw IshRuntimeDriverError.supervisorCommandRejected(
                        "IshError \(code): \(message)"
                    )
                } catch IshError.raw(let code, _) where code == -18 {
                    // The native reader has terminalized this session and
                    // requested bounded fail-close cleanup after its output
                    // backlog was exhausted. The deferred close completes or
                    // escalates that cleanup before releasing the session.
                    throw IshRuntimeDriverError.nativeOutputLimitExceeded(
                        maximumBytes: 4 * 1_024 * 1_024,
                        maximumFrames: 4_096
                    )
                }

                switch event {
                case .data(let data, kind: .stdout, seq: _):
                    try cancellation.check()
                    try append(
                        data,
                        to: &standardOutput,
                        limit: request.maximumStandardOutputBytes,
                        stream: "stdout"
                    )
                case .data(let data, kind: .stderr, seq: _):
                    try cancellation.check()
                    try append(
                        data,
                        to: &standardError,
                        limit: request.maximumStandardErrorBytes,
                        stream: "stderr"
                    )
                case .exited(let exitCode, let signal):
                    try IshRuntimeTransportPolicy.validateAuthoritativeExit(
                        exitCode: exitCode,
                        signal: signal
                    )
                    return IshDriverCommandResult(
                        exitCode: exitCode,
                        signal: signal,
                        standardOutput: standardOutput,
                        standardError: standardError,
                        timedOut: false
                    )
                }
            }
        } catch let error as IshRuntimeDriverError {
            switch error {
            case .supervisorCommandRejected:
                // ERROR is terminal in wire v4. The supervisor either rejected
                // the spawn or force-closed the tracked session; deferred close
                // releases the host handle without sending a second terminate.
                try cancellation.check()
                throw error
            case .nativeOutputLimitExceeded:
                // Native already requested SESSION_CLOSE when it published the
                // terminal backlog status. Deferred close waits for reap and
                // fail-closes the instance if that acknowledgement is missing.
                // Because close is void, the runtime conservatively requires a
                // restart for every native backlog overflow.
                throw error
            case .sessionTerminationUnconfirmed:
                throw error
            case .outputLimitExceeded:
                if !terminationConfirmed {
                    try terminateAndConfirmExit(session)
                }
                try cancellation.check()
                throw error
            }
        } catch is CancellationError {
            // Cancellation is acknowledged only after the guest process has an
            // authoritative EXITED event. A cleanup failure replaces
            // CancellationError and forces the runtime into fail-close.
            try terminateAndConfirmExit(session)
            throw CancellationError()
        } catch {
            let executionError = error
            try terminateAndConfirmExit(session)
            try cancellation.check()
            throw executionError
        }
    }

    private func timedOutResult(
        standardOutput: Data = Data(),
        standardError: Data = Data()
    ) -> IshDriverCommandResult {
        IshDriverCommandResult(
            exitCode: -1,
            signal: 0,
            standardOutput: standardOutput,
            standardError: standardError,
            timedOut: true
        )
    }

    private func append(
        _ data: Data,
        to buffer: inout Data,
        limit: Int,
        stream: String
    ) throws {
        guard data.count <= limit, buffer.count <= limit - data.count else {
            throw IshRuntimeDriverError.outputLimitExceeded(
                stream: stream,
                limit: limit
            )
        }
        buffer.append(data)
    }

    private struct TerminationDrainResult {
        let standardOutput: Data
        let standardError: Data
        let outputLimitError: IshRuntimeDriverError?
    }

    @discardableResult
    private func terminateAndConfirmExit(
        _ session: IshSession,
        preserving initialStandardOutput: Data? = nil,
        standardError initialStandardError: Data? = nil,
        maximumStandardOutputBytes: Int = 0,
        maximumStandardErrorBytes: Int = 0
    ) throws -> TerminationDrainResult {
        do {
            try session.terminate()
        } catch {
            throw IshRuntimeDriverError.sessionTerminationUnconfirmed(
                "terminate request failed: \(error.localizedDescription)"
            )
        }

        let deadline = ProcessInfo.processInfo.systemUptime
            + terminationConfirmationTimeout
        let preservesOutput = initialStandardOutput != nil
            && initialStandardError != nil
        var standardOutput = initialStandardOutput ?? Data()
        var standardError = initialStandardError ?? Data()
        var outputLimitError: IshRuntimeDriverError?
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else {
                throw IshRuntimeDriverError.sessionTerminationUnconfirmed(
                    "no EXITED event arrived within "
                        + "\(terminationConfirmationTimeout) seconds"
                )
            }

            do {
                switch try session.read(timeout: min(remaining, 0.25)) {
                case .data(let data, kind: .stdout, seq: _):
                    if preservesOutput, outputLimitError == nil {
                        do {
                            try append(
                                data,
                                to: &standardOutput,
                                limit: maximumStandardOutputBytes,
                                stream: "stdout"
                            )
                        } catch let error as IshRuntimeDriverError {
                            outputLimitError = error
                        }
                    }
                case .data(let data, kind: .stderr, seq: _):
                    if preservesOutput, outputLimitError == nil {
                        do {
                            try append(
                                data,
                                to: &standardError,
                                limit: maximumStandardErrorBytes,
                                stream: "stderr"
                            )
                        } catch let error as IshRuntimeDriverError {
                            outputLimitError = error
                        }
                    }
                case .exited(let exitCode, let signal):
                    try IshRuntimeTransportPolicy.validateAuthoritativeExit(
                        exitCode: exitCode,
                        signal: signal
                    )
                    return TerminationDrainResult(
                        standardOutput: standardOutput,
                        standardError: standardError,
                        outputLimitError: outputLimitError
                    )
                }
            } catch IshError.raw(let code, _) where code == -12 {
                continue
            } catch {
                throw IshRuntimeDriverError.sessionTerminationUnconfirmed(
                    "reading the EXITED event failed: \(error.localizedDescription)"
                )
            }
        }
    }

    func shutdown() throws {
        // v0.4.0-abi.6 asks the supervisor to stop, soft-halts the embedded
        // kernel, joins its pthread, and returns to Swift. The underlying iSH
        // process-global state still permits only one boot/shutdown lifecycle.
        try IshInstance.shared.shutdown()
    }
}
#endif
