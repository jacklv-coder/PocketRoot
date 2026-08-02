import Foundation

enum TerminalSpecialKey: CaseIterable, Equatable {
    case escape
    case tab
    case interrupt
    case endOfFile
    case historyPrevious
    case historyNext

    var title: String {
        switch self {
        case .escape: "Esc"
        case .tab: "Tab"
        case .interrupt: "Ctrl-C"
        case .endOfFile: "Ctrl-D"
        case .historyPrevious: "↑"
        case .historyNext: "↓"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .escape: "PocketRootTerminal.key.escape"
        case .tab: "PocketRootTerminal.key.tab"
        case .interrupt: "PocketRootTerminal.key.ctrl-c"
        case .endOfFile: "PocketRootTerminal.key.ctrl-d"
        case .historyPrevious: "PocketRootTerminal.key.up"
        case .historyNext: "PocketRootTerminal.key.down"
        }
    }

    func input(applicationCursorMode: Bool) -> Data {
        switch self {
        case .escape: Data([0x1b])
        case .tab: Data([0x09])
        case .interrupt: Data([0x03])
        case .endOfFile: Data([0x04])
        case .historyPrevious:
            Data(applicationCursorMode ? [0x1b, 0x4f, 0x41] : [0x1b, 0x5b, 0x41])
        case .historyNext:
            Data(applicationCursorMode ? [0x1b, 0x4f, 0x42] : [0x1b, 0x5b, 0x42])
        }
    }
}

enum TerminalAccessoryControl {
    static let dismissKeyboardAccessibilityIdentifier =
        "PocketRootTerminal.key.dismiss-keyboard"
}
