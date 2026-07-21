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
}
