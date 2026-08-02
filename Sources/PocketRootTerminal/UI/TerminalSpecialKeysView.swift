#if canImport(UIKit)
import UIKit

@MainActor
final class TerminalSpecialKeysView: UIInputView {
    var onKeyPress: ((TerminalSpecialKey) -> Void)?
    var onDismissKeyboard: (() -> Void)?

    private var buttons: [UIButton] = []

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 44)
    }

    convenience init() {
        self.init(
            frame: CGRect(x: 0, y: 0, width: 0, height: 44),
            inputViewStyle: .keyboard
        )
    }

    override init(frame: CGRect, inputViewStyle: UIInputView.Style) {
        super.init(frame: frame, inputViewStyle: inputViewStyle)
        allowsSelfSizing = true
        setUpView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpView()
    }

    func setInputEnabled(_ isEnabled: Bool) {
        buttons.forEach { $0.isEnabled = isEnabled }
        alpha = isEnabled ? 1 : 0.6
    }

    private func setUpView() {
        autoresizingMask = [.flexibleWidth]
        backgroundColor = .secondarySystemBackground

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fillProportionally
        stackView.spacing = 4
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 4,
            leading: 8,
            bottom: 4,
            trailing: 8
        )

        for key in TerminalSpecialKey.allCases {
            let button = makeButton(for: key)
            buttons.append(button)
            stackView.addArrangedSubview(button)
        }
        let dismissKeyboardButton = makeDismissKeyboardButton()
        dismissKeyboardButton.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        stackView.addArrangedSubview(dismissKeyboardButton)

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            dismissKeyboardButton.widthAnchor.constraint(
                greaterThanOrEqualToConstant: 44
            )
        ])
    }

    private func makeButton(for key: TerminalSpecialKey) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.gray()
        configuration.title = key.title
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 6,
            leading: 8,
            bottom: 6,
            trailing: 8
        )
        button.configuration = configuration
        button.accessibilityLabel = key.title
        button.accessibilityIdentifier = key.accessibilityIdentifier
        button.addAction(
            UIAction { [weak self] _ in
                self?.onKeyPress?(key)
            },
            for: .touchUpInside
        )
        return button
    }

    private func makeDismissKeyboardButton() -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.gray()
        configuration.image = UIImage(
            systemName: "keyboard.chevron.compact.down"
        )
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 6,
            leading: 8,
            bottom: 6,
            trailing: 8
        )
        button.configuration = configuration
        button.accessibilityLabel = "Hide keyboard"
        button.accessibilityIdentifier =
            TerminalAccessoryControl.dismissKeyboardAccessibilityIdentifier
        button.addAction(
            UIAction { [weak self] _ in
                self?.onDismissKeyboard?()
            },
            for: .touchUpInside
        )
        return button
    }
}
#endif
