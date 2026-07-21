#if canImport(UIKit)
import UIKit

@MainActor
final class TerminalPlaceholderView: UIView {
    private let textView = UITextView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpView()
    }

    func render(text: String, theme: PocketRootTerminalTheme) {
        textView.text = text
        textView.backgroundColor = theme.backgroundColor
        textView.textColor = theme.foregroundColor
        textView.font = theme.font
        backgroundColor = theme.backgroundColor
    }

    private func setUpView() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        clipsToBounds = true

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        textView.accessibilityIdentifier = "PocketRootTerminal.output"

        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
#endif
