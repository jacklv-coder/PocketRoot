import Foundation

/// A platform-neutral description of the terminal's visual appearance.
public struct PocketRootTerminalTheme: Sendable, Equatable {
    public enum Palette: String, Sendable, CaseIterable {
        case system
        case dark
    }

    public let palette: Palette
    public let fontSize: Double

    public init(
        palette: Palette = .system,
        fontSize: Double = 14
    ) {
        self.palette = palette
        self.fontSize = fontSize
    }

    public static let system = PocketRootTerminalTheme()
    public static let dark = PocketRootTerminalTheme(palette: .dark)
}

#if canImport(UIKit)
import UIKit

extension PocketRootTerminalTheme {
    @MainActor
    var backgroundColor: UIColor {
        switch palette {
        case .system:
            return .secondarySystemBackground
        case .dark:
            return UIColor(red: 0.05, green: 0.06, blue: 0.07, alpha: 1)
        }
    }

    @MainActor
    var foregroundColor: UIColor {
        switch palette {
        case .system:
            return .label
        case .dark:
            return UIColor(red: 0.70, green: 0.95, blue: 0.72, alpha: 1)
        }
    }

    @MainActor
    var font: UIFont {
        let baseFont = UIFont.monospacedSystemFont(
            ofSize: CGFloat(max(fontSize, 1)),
            weight: .regular
        )
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: baseFont)
    }
}
#endif
