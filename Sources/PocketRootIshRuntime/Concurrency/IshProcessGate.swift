import Foundation
import PocketRootCore

/// Owns the single IshEmbed process slot and prevents unrelated runtime
/// adapters from issuing native calls against the same singleton.
actor IshProcessGate {
    static let shared = IshProcessGate()

    private enum State: Equatable {
        case available
        case claimed(UUID)
        case terminated
    }

    private var state: State = .available

    func claim(for ownerID: UUID) throws {
        switch state {
        case .available:
            state = .claimed(ownerID)
        case .claimed(let claimedOwnerID) where claimedOwnerID == ownerID:
            return
        case .claimed:
            throw PocketRootError.runtimeFailure(
                "The process-global IshEmbed instance is owned by another PocketRoot system."
            )
        case .terminated:
            throw PocketRootError.restartRequired
        }
    }

    func requireOwnership(for ownerID: UUID) throws {
        switch state {
        case .claimed(let claimedOwnerID) where claimedOwnerID == ownerID:
            return
        case .terminated:
            throw PocketRootError.restartRequired
        case .available, .claimed:
            throw PocketRootError.runtimeFailure(
                "This PocketRoot system does not own the process-global IshEmbed instance."
            )
        }
    }

    func markTerminated(for ownerID: UUID) {
        guard state == .claimed(ownerID) else {
            return
        }
        state = .terminated
    }
}
