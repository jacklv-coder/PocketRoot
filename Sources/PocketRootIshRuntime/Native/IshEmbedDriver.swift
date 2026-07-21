#if os(iOS) && arch(arm64) && canImport(IshEmbed)
import Foundation
import IshEmbed

struct IshEmbedDriver: IshRuntimeDriver {
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
        try session.closeStdin()

        var standardOutput = Data()
        var standardError = Data()
        let deadline = ProcessInfo.processInfo.systemUptime + request.timeout

        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else {
                try? session.terminate(graceMs: 0)
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
                    stream: "stdout",
                    session: session
                )
            case .data(let data, kind: .stderr, seq: _):
                try append(
                    data,
                    to: &standardError,
                    limit: request.maximumStandardErrorBytes,
                    stream: "stderr",
                    session: session
                )
            case .exited(let exitCode, let signal):
                return IshDriverCommandResult(
                    exitCode: exitCode,
                    signal: signal,
                    standardOutput: standardOutput,
                    standardError: standardError,
                    timedOut: false
                )
            }
        }
    }

    private func append(
        _ data: Data,
        to buffer: inout Data,
        limit: Int,
        stream: String,
        session: IshSession
    ) throws {
        guard data.count <= limit, buffer.count <= limit - data.count else {
            try? session.terminate(graceMs: 0)
            throw IshRuntimeDriverError.outputLimitExceeded(
                stream: stream,
                limit: limit
            )
        }
        buffer.append(data)
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
