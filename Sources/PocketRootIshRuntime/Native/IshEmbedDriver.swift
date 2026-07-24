#if os(iOS) && arch(arm64) && canImport(IshEmbed)
import Foundation
import IshEmbed

struct IshEmbedDriver: IshRuntimeDriver {
    private let terminationConfirmationTimeout: TimeInterval = 3
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
        let session: IshSession
        do {
            session = try IshInstance.shared.spawn(
                .init(
                    argv: request.arguments,
                    cwd: request.workingDirectory,
                    env: request.environment,
                    mergeStderrIntoStdout: request.mergeStandardError,
                    timeout: nil
                )
            )
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
        do {
            try session.closeStdin()

            var standardOutput = Data()
            var standardError = Data()
            let deadline = ProcessInfo.processInfo.systemUptime + request.timeout

            while true {
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                guard remaining > 0 else {
                    try terminateAndConfirmExit(session)
                    return IshDriverCommandResult(
                        exitCode: -1,
                        signal: 0,
                        standardOutput: standardOutput,
                        standardError: standardError,
                        timedOut: true
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
                    try append(
                        data,
                        to: &standardOutput,
                        limit: request.maximumStandardOutputBytes,
                        stream: "stdout"
                    )
                case .data(let data, kind: .stderr, seq: _):
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
                try terminateAndConfirmExit(session)
                throw error
            }
        } catch {
            let executionError = error
            try terminateAndConfirmExit(session)
            throw executionError
        }
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

    private func terminateAndConfirmExit(_ session: IshSession) throws {
        do {
            try session.terminate()
        } catch {
            throw IshRuntimeDriverError.sessionTerminationUnconfirmed(
                "terminate request failed: \(error.localizedDescription)"
            )
        }

        let deadline = ProcessInfo.processInfo.systemUptime
            + terminationConfirmationTimeout
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
                case .data:
                    // Drain already queued output while waiting for the
                    // authoritative process-exit event.
                    continue
                case .exited(let exitCode, let signal):
                    try IshRuntimeTransportPolicy.validateAuthoritativeExit(
                        exitCode: exitCode,
                        signal: signal
                    )
                    return
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
        // v0.4.0-abi.3 asks the supervisor to stop, soft-halts the embedded
        // kernel, joins its pthread, and returns to Swift. The underlying iSH
        // process-global state still permits only one boot/shutdown lifecycle.
        try IshInstance.shared.shutdown()
    }
}
#endif
