import Foundation

@available(macOS 13.0, *)
public struct PocketRootLinuxCommand: Sendable, Equatable {
    public let toolCallID: String
    public let command: String
    public let workingDirectory: String
    public let environment: [String: String]
    public let timeoutSeconds: Int
    public let mergeStandardError: Bool

    public init(
        toolCallID: String,
        command: String,
        workingDirectory: String,
        environment: [String: String],
        timeoutSeconds: Int,
        mergeStandardError: Bool
    ) {
        self.toolCallID = toolCallID
        self.command = command
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeoutSeconds = timeoutSeconds
        self.mergeStandardError = mergeStandardError
    }
}

public enum PocketRootLinuxCommandPolicyDecision: Sendable, Equatable {
    case allowed
    case denied(reason: String)
}

@available(macOS 13.0, *)
public struct PocketRootLinuxCommandPolicy: Sendable {
    private let evaluator: @Sendable (
        PocketRootLinuxCommand
    ) -> PocketRootLinuxCommandPolicyDecision

    public init(
        _ evaluator: @escaping @Sendable (
            PocketRootLinuxCommand
        ) -> PocketRootLinuxCommandPolicyDecision
    ) {
        self.evaluator = evaluator
    }

    public func evaluate(
        _ command: PocketRootLinuxCommand
    ) -> PocketRootLinuxCommandPolicyDecision {
        evaluator(command)
    }

    public static let denyAll = Self { _ in
        .denied(reason: "The host command policy denied this request.")
    }

    public static func exactCommands(
        _ allowedCommands: Set<String>
    ) -> Self {
        Self { command in
            guard allowedCommands.contains(command.command) else {
                return .denied(
                    reason: "The command is not in the host allowlist."
                )
            }
            return .allowed
        }
    }
}

public enum PocketRootLinuxCommandApprovalDecision: Sendable, Equatable {
    case approved
    case denied(reason: String)
}

@available(macOS 13.0, *)
public struct PocketRootLinuxCommandApproval: Sendable {
    private let requester: @Sendable (
        PocketRootLinuxCommand
    ) async -> PocketRootLinuxCommandApprovalDecision

    public init(
        _ requester: @escaping @Sendable (
            PocketRootLinuxCommand
        ) async -> PocketRootLinuxCommandApprovalDecision
    ) {
        self.requester = requester
    }

    public func request(
        _ command: PocketRootLinuxCommand
    ) async -> PocketRootLinuxCommandApprovalDecision {
        await requester(command)
    }
}
