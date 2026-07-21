import Foundation

/// Configuration for the placeholder terminal surface.
///
/// The first milestone does not launch a shell. These values intentionally
/// describe only presentation and input behavior so the API can remain useful
/// when a real terminal backend is connected later.
public struct PocketRootTerminalConfiguration: Sendable, Equatable {
    public let placeholderText: String
    public let prompt: String
    public let allowsInput: Bool
    public let showsAccessoryView: Bool

    public init(
        placeholderText: String = "Terminal integration pending",
        prompt: String = "$ ",
        allowsInput: Bool = false,
        showsAccessoryView: Bool = true
    ) {
        self.placeholderText = placeholderText
        self.prompt = prompt
        self.allowsInput = allowsInput
        self.showsAccessoryView = showsAccessoryView
    }
}
