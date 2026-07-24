import Foundation

/// Keeps synchronous IshEmbed calls off Swift cooperative and UI executors.
final class BlockingIshExecutor: @unchecked Sendable {
    /// IshEmbed exposes one process-global instance. Production adapters must
    /// therefore share one serial queue even when callers create more than one
    /// PocketRootSystem.
    static let shared = BlockingIshExecutor()

    private let queue: DispatchQueue

    init(label: String = "com.jacklv.PocketRoot.IshRuntime") {
        queue = DispatchQueue(label: label, qos: .userInitiated)
    }

    @available(macOS 13.0, *)
    func perform<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try Task.checkCancellation()

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @available(macOS 13.0, *)
    func performCancellable<T: Sendable>(
        _ operation: @escaping @Sendable (IshCommandCancellation) throws -> T
    ) async throws -> T {
        try Task.checkCancellation()
        let cancellation = IshCommandCancellation()

        return try await withTaskCancellationHandler {
            let result = try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    do {
                        try cancellation.check()
                        let result = try operation(cancellation)
                        try cancellation.check()
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            // Cancellation can race with the queue's final token check and
            // continuation resume. The resumed Task is the final authority.
            try Task.checkCancellation()
            return result
        } onCancel: {
            cancellation.cancel()
        }
    }
}
