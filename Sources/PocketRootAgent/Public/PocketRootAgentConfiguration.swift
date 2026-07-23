public struct PocketRootAgentConfiguration: Sendable, Equatable {
    public let instructions: String
    public let maximumTurns: Int
    public let maximumToolCalls: Int
    public let maximumUserInputBytes: Int
    public let maximumModelOutputBytes: Int
    public let maximumToolArgumentsBytes: Int
    public let maximumToolOutputBytes: Int

    public init(
        instructions: String,
        maximumTurns: Int = 8,
        maximumToolCalls: Int = 16,
        maximumUserInputBytes: Int = 64 * 1_024,
        maximumModelOutputBytes: Int = 256 * 1_024,
        maximumToolArgumentsBytes: Int = 64 * 1_024,
        maximumToolOutputBytes: Int = 64 * 1_024
    ) {
        self.instructions = instructions
        self.maximumTurns = maximumTurns
        self.maximumToolCalls = maximumToolCalls
        self.maximumUserInputBytes = maximumUserInputBytes
        self.maximumModelOutputBytes = maximumModelOutputBytes
        self.maximumToolArgumentsBytes = maximumToolArgumentsBytes
        self.maximumToolOutputBytes = maximumToolOutputBytes
    }
}
