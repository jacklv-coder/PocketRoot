import Foundation

/// Bridges cooperative Swift Task cancellation into the synchronous native
/// command loop without blocking the cancelling executor.
final class IshCommandCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func check() throws {
        if isCancelled {
            throw CancellationError()
        }
    }
}
