import Foundation
import PocketRootCore

@available(macOS 13.0, *)
final class IshPocketRootSession: PocketRootSession, @unchecked Sendable {
    // IshEmbed can deliver a single 1 MiB frame. Split those frames before
    // entering AsyncStream so its element-count policy also enforces a
    // predictable byte ceiling.
    private static let maximumOutputChunkBytes = 16 * 1_024
    private static let maximumBufferedOutputBytes = 4 * 1_024 * 1_024
    private static let eventBufferCapacity =
        maximumBufferedOutputBytes / maximumOutputChunkBytes

    let id: UUID
    let configuration: PocketRootSessionConfiguration
    let events: AsyncStream<PocketRootSessionEvent>

    private let controller: IshPocketRootSessionController

    init(
        id: UUID,
        configuration: PocketRootSessionConfiguration,
        driverSession: any IshRuntimeDriverSession,
        executor: BlockingIshExecutor,
        onClosed: @escaping @Sendable (UUID) async -> Void,
        onFailure: @escaping @Sendable (UUID, IshRuntimeDriverError) async -> Void
    ) {
        self.id = id
        self.configuration = configuration

        let stream = AsyncStream.makeStream(
            of: PocketRootSessionEvent.self,
            // Newest preserves terminal .failed/.exited events if output fills
            // the buffer. Output is chunked to 16 KiB, so 256 retained events
            // hold at most 4 MiB of payload rather than 256 native 1 MiB frames.
            bufferingPolicy: .bufferingNewest(Self.eventBufferCapacity)
        )
        events = stream.stream
        controller = IshPocketRootSessionController(
            id: id,
            driverSession: driverSession,
            executor: executor,
            continuation: stream.continuation,
            maximumOutputChunkBytes: Self.maximumOutputChunkBytes,
            onClosed: onClosed,
            onFailure: onFailure
        )
        stream.continuation.onTermination = { [weak controller] _ in
            Task {
                await controller?.consumerTerminated()
            }
        }
    }

    func start() async {
        await controller.start()
    }

    func write(_ data: Data) async throws {
        try await controller.write(data)
    }

    func resize(to size: PocketRootTerminalSize) async throws {
        try await controller.resize(to: size)
    }

    func sendSignal(_ signal: Int32) async throws {
        try await controller.sendSignal(signal)
    }

    func closeInput() async throws {
        try await controller.closeInput()
    }

    func terminate() async {
        await controller.terminate()
    }

    func cancelCreation() async {
        await controller.cancelCreation()
    }
}

@available(macOS 13.0, *)
private actor IshPocketRootSessionController {
    private enum State {
        case initialized
        case running
        case terminating
        case closing
        case closed
    }

    private enum OutputPublishResult {
        case accepted
        case overflow
        case consumerTerminated
    }

    private static let maximumWriteBytes = 64 * 1_024
    private static let terminationTimeout: Duration = .seconds(6)

    private let id: UUID
    private let driverSession: any IshRuntimeDriverSession
    private let executor: BlockingIshExecutor
    private let continuation: AsyncStream<PocketRootSessionEvent>.Continuation
    private let maximumOutputChunkBytes: Int
    private let onClosed: @Sendable (UUID) async -> Void
    private let onFailure: @Sendable (UUID, IshRuntimeDriverError) async -> Void

    private var state: State = .initialized
    private var readTask: Task<Void, Never>?
    private var terminationRequested = false

    init(
        id: UUID,
        driverSession: any IshRuntimeDriverSession,
        executor: BlockingIshExecutor,
        continuation: AsyncStream<PocketRootSessionEvent>.Continuation,
        maximumOutputChunkBytes: Int,
        onClosed: @escaping @Sendable (UUID) async -> Void,
        onFailure: @escaping @Sendable (UUID, IshRuntimeDriverError) async -> Void
    ) {
        self.id = id
        self.driverSession = driverSession
        self.executor = executor
        self.continuation = continuation
        self.maximumOutputChunkBytes = maximumOutputChunkBytes
        self.onClosed = onClosed
        self.onFailure = onFailure
    }

    func start() {
        guard case .initialized = state else {
            return
        }
        state = .running
        continuation.yield(.started)
        readTask = Task { [weak self] in
            await self?.readEvents()
        }
    }

    func write(_ data: Data) async throws {
        guard case .running = state else {
            throw PocketRootError.runtimeFailure(
                "The interactive terminal session is not accepting input."
            )
        }
        guard !data.isEmpty else {
            return
        }
        guard data.count <= Self.maximumWriteBytes else {
            throw PocketRootError.invalidCommandRequest(
                "A terminal input write cannot exceed \(Self.maximumWriteBytes) bytes."
            )
        }

        do {
            try await executor.perform { [driverSession] in
                try driverSession.write(data)
            }
        } catch {
            await failClosedIfRequired(error)
            throw map(error)
        }
    }

    func resize(to size: PocketRootTerminalSize) async throws {
        guard case .running = state else {
            return
        }
        do {
            try await executor.perform { [driverSession] in
                try driverSession.resize(to: size)
            }
        } catch {
            await failClosedIfRequired(error)
            throw map(error)
        }
    }

    func sendSignal(_ signal: Int32) async throws {
        guard case .running = state else {
            throw PocketRootError.runtimeFailure(
                "The interactive terminal session is not running."
            )
        }
        guard signal > 0, signal < 128 else {
            throw PocketRootError.invalidCommandRequest(
                "signal must be in the range 1...127."
            )
        }
        do {
            try await executor.perform { [driverSession] in
                try driverSession.sendSignal(signal)
            }
        } catch {
            await failClosedIfRequired(error)
            throw map(error)
        }
    }

    func closeInput() async throws {
        guard case .running = state else {
            return
        }
        do {
            try await executor.perform { [driverSession] in
                try driverSession.closeInput()
            }
        } catch {
            await failClosedIfRequired(error)
            throw map(error)
        }
    }

    func terminate() async {
        let shouldRequestTermination: Bool
        switch state {
        case .initialized:
            await finishWithFailure(
                "The interactive terminal was terminated before it started."
            )
            return
        case .running:
            state = .terminating
            shouldRequestTermination = true
        case .terminating:
            shouldRequestTermination = !terminationRequested
        case .closing:
            shouldRequestTermination = false
        case .closed:
            return
        }

        if shouldRequestTermination {
            terminationRequested = true
            do {
                try await executor.perform { [driverSession] in
                    try driverSession.terminate()
                }
            } catch {
                await finishWithFailure(
                    "Unable to terminate the interactive terminal: "
                        + error.localizedDescription,
                    cause: error
                )
                return
            }
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.terminationTimeout)
        while state != .closed, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        if state != .closed {
            if state == .closing {
                await onFailure(
                    id,
                    .sessionTerminationUnconfirmed(
                        "the native session close did not finish within six seconds"
                    )
                )
            } else {
                await finishWithFailure(
                    "The interactive terminal did not confirm exit within six seconds.",
                    cause: IshRuntimeDriverError.sessionTerminationUnconfirmed(
                        "interactive session exit was not observed within six seconds"
                    )
                )
            }
        }
    }

    func consumerTerminated() async {
        guard state != .closed else {
            return
        }
        await terminate()
    }

    func cancelCreation() async {
        guard state != .closing, state != .closed else {
            return
        }
        state = .closing
        readTask?.cancel()
        readTask = nil
        await closeNativeSession()
        continuation.finish()
        state = .closed
    }

    private func readEvents() async {
        while !Task.isCancelled {
            guard state == .running || state == .terminating else {
                return
            }

            do {
                let event = try await executor.perform { [driverSession] in
                    try driverSession.read(timeout: 0.1)
                }
                guard let event else {
                    continue
                }
                switch event {
                case .standardOutput(let data):
                    switch publishOutput(data, asStandardError: false) {
                    case .accepted:
                        break
                    case .overflow:
                        await finishWithFailure(
                            "The terminal output consumer could not keep up with the guest."
                        )
                        return
                    case .consumerTerminated:
                        // onTermination requests an orderly terminate. Keep the
                        // sole read loop alive so it can observe EXITED.
                        continue
                    }
                case .standardError(let data):
                    switch publishOutput(data, asStandardError: true) {
                    case .accepted:
                        break
                    case .overflow:
                        await finishWithFailure(
                            "The terminal output consumer could not keep up with the guest."
                        )
                        return
                    case .consumerTerminated:
                        continue
                    }
                case .exited(let exitCode, _):
                    await finishNormally(exitCode: exitCode)
                    return
                }
            } catch {
                guard state != .closed else {
                    return
                }
                await finishWithFailure(
                    "Interactive terminal transport failed: \(error.localizedDescription)",
                    cause: error
                )
                return
            }
        }
    }

    private func publishOutput(
        _ data: Data,
        asStandardError: Bool
    ) -> OutputPublishResult {
        guard !data.isEmpty else {
            return .accepted
        }

        var offset = 0
        while offset < data.count {
            let end = min(offset + maximumOutputChunkBytes, data.count)
            let chunk = Data(data[offset..<end])
            let event: PocketRootSessionEvent = asStandardError
                ? .standardError(chunk)
                : .standardOutput(chunk)
            switch continuation.yield(event) {
            case .enqueued:
                offset = end
            case .dropped:
                // bufferingNewest retained the current chunk and discarded the
                // oldest event. Stop immediately and publish a terminal failure.
                return .overflow
            case .terminated:
                return .consumerTerminated
            @unknown default:
                return .overflow
            }
        }
        return .accepted
    }

    private func finishNormally(exitCode: Int32) async {
        guard state != .closing, state != .closed else {
            return
        }
        state = .closing
        readTask = nil
        continuation.yield(.exited(exitCode))
        continuation.finish()
        await closeNativeSession()
        state = .closed
    }

    private func finishWithFailure(
        _ message: String,
        cause: Error? = nil
    ) async {
        guard state != .closing, state != .closed else {
            return
        }
        state = .closing
        // Do not cancel here: this method is commonly entered by readTask
        // itself. Self-cancellation would make BlockingIshExecutor reject the
        // native close before it reaches the serial queue. A read is bounded
        // to 100 ms, and the closed state prevents another polling iteration.
        readTask = nil
        let failure = (cause as? IshRuntimeDriverError)
            ?? IshRuntimeDriverError.sessionTerminationUnconfirmed(
            cause.map {
                "\(message) (\($0.localizedDescription))"
            } ?? message
        )
        await onFailure(id, failure)
        await closeNativeSession()
        // bufferingNewest guarantees this terminal event displaces old output
        // instead of being dropped when the byte-bounded buffer is full.
        continuation.yield(.failed(message))
        continuation.finish()
        state = .closed
    }

    private func closeNativeSession() async {
        _ = try? await executor.performCleanup { [driverSession] in
            driverSession.close()
        }
        await onClosed(id)
    }

    private func failClosedIfRequired(_ error: Error) async {
        guard let driverError = error as? IshRuntimeDriverError,
              driverError.requiresRuntimeRestart
        else {
            return
        }
        await finishWithFailure(
            "Interactive terminal transport failed: \(error.localizedDescription)",
            cause: error
        )
    }

    private func map(_ error: Error) -> PocketRootError {
        if let error = error as? PocketRootError {
            return error
        }
        if let description = (error as? LocalizedError)?.errorDescription {
            return .runtimeFailure(description)
        }
        return .runtimeFailure(String(describing: error))
    }
}
