import SwiftUI
import UIKit

/// Entry point of the keyboard extension (NSExtensionPrincipalClass).
final class KeyboardViewController: UIInputViewController {
    private let controller = KeyboardController()
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        controller.proxyTarget.viewController = self
        controller.onGlobe = { [weak self] view, event in self?.handleInputModeList(from: view, with: event) }
        controller.onHeightChange = { [weak self] height in self?.setHeight(height) }
        controller.insertIntoHost = { [weak self] text in self?.textDocumentProxy.insertText(text) }

        let host = UIHostingController(rootView: KeyboardRootView(c: controller))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        setHeight(controller.totalHeight)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        controller.update(width: view.bounds.width, showGlobe: needsInputModeSwitchKey)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        controller.viewHeightChanged(view.bounds.height)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        syncWithHost()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        controller.persist()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        syncWithHost()
    }

    private func syncWithHost() {
        controller.hostTextChanged(autoCapitalize: (textDocumentProxy.autocapitalizationType ?? .sentences) != .none)
    }

    private func setHeight(_ height: Double) {
        if let heightConstraint {
            heightConstraint.constant = height
        } else {
            let c = view.heightAnchor.constraint(equalToConstant: height)
            c.priority = UILayoutPriority(999)
            c.isActive = true
            heightConstraint = c
        }
    }
}
