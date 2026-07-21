#if canImport(UIKit)
import UIKit

@MainActor
final class TerminalAccessoryView: UIView {
    var onSubmit: ((String) -> Void)?

    private let textField = UITextField()
    private let sendButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpView()
    }

    func configure(prompt: String, isInputEnabled: Bool) {
        textField.placeholder = prompt + "command"
        textField.isEnabled = isInputEnabled
        sendButton.isEnabled = isInputEnabled
        alpha = isInputEnabled ? 1 : 0.6
    }

    private func setUpView() {
        translatesAutoresizingMaskIntoConstraints = false

        textField.borderStyle = .roundedRect
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.returnKeyType = .send
        textField.accessibilityIdentifier = "PocketRootTerminal.command"
        textField.addTarget(self, action: #selector(submit), for: .editingDidEndOnExit)

        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.title = "Send"
        sendButton.configuration = buttonConfiguration
        sendButton.accessibilityIdentifier = "PocketRootTerminal.send"
        sendButton.addTarget(self, action: #selector(submit), for: .touchUpInside)

        let stackView = UIStackView(arrangedSubviews: [textField, sendButton])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.spacing = 8

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            textField.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            sendButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])
    }

    @objc
    private func submit() {
        guard let command = textField.text else {
            return
        }

        onSubmit?(command)
        textField.text = nil
    }
}
#endif
