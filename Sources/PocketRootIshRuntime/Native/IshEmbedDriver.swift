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
        let session = try IshInstance.shared.spawn(
            .init(
                argv: request.arguments,
                cwd: request.workingDirectory,
                env: request.environment,
                mergeStderrIntoStdout: request.mergeStandardError,
                timeout: nil
            )
        )
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
            case .ambiguousTransportExitMarker:
                // The event may be a real guest `exit 17` or a dead reader
                // transport. Explicitly request termination and attempt to
                // observe a second authoritative exit before failing closed.
                try terminateAndConfirmExit(session)
                throw IshRuntimeDriverError.sessionTerminationUnconfirmed(
                    "the pinned transport emitted an ambiguous EXITED marker"
                )
            case .supervisorCommandRejected:
                // In pinned v0.3.3, negative synthetic exits come only from a
                // supervisor ERROR emitted after spawn was rejected and its
                // session was freed; no guest process exists to terminate.
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
        // The pinned iSH kernel's halt path ends in _exit(0). On a real iOS
        // build this call normally terminates the entire host App process and
        // therefore does not return. The return path remains useful for test
        // drivers and for a future upstream implementation with softer
        // shutdown semantics.
        try IshInstance.shared.shutdown()
    }
}
#endif
