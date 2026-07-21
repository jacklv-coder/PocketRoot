public enum PocketRootRuntimeState: Sendable, Equatable {
    case idle
    case preparingRootFS
    case booting
    case ready
    case shuttingDown
    case failed(String)
}
