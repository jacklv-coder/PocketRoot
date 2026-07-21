import Foundation

public enum PocketRootSessionEvent: Sendable, Equatable {
    case started
    case standardOutput(Data)
    case standardError(Data)
    case exited(Int32)
    case failed(String)
}
