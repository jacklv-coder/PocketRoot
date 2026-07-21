public enum PocketRootRuntimeState: Sendable, Equatable {
    case idle
    case preparingRootFS
    case booting
    case ready
    case shuttingDown
    /// The embedded runtime has shut down and the host process must restart
    /// before a new runtime can be booted.
    case terminated
    case failed(String)
}
