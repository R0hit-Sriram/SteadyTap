import SwiftUI
import UIKit

/// A tap target whose touches are handled by UIKit rather than SwiftUI.
///
/// Why this exists: the keyboard's controller republishes after every keystroke, so the toolbar is
/// rebuilt constantly. A SwiftUI gesture that is torn down and recreated part-way through a touch
/// never delivers its end, and the tap is silently dropped — which is why ⚙︎ sometimes needed two
/// or three presses. The keys themselves never had this problem because they are a plain UIView
/// that reads touches directly, and this does the same.
///
/// It also keeps its own pressed state in UIKit, so holding a finger down does not trigger a SwiftUI
/// redraw, and it accepts a touch that wanders: a shaky finger that slides on the way up still counts.
final class TapTargetView: UIView {
    var action: (() -> Void)?
    var isEnabled = true { didSet { if !isEnabled { setPressed(false) } } }
    /// How far outside the button the finger may be when it lifts and still count.
    var slop: CGFloat = 36
    var cornerRadius: CGFloat = 10 { didSet { layer.cornerRadius = cornerRadius } }

    private var tracking: UITouch?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        isAccessibilityElement = false   // SwiftUI supplies the label and action
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func setPressed(_ on: Bool) {
        // Done in UIKit on purpose: no SwiftUI state changes while a finger is down.
        backgroundColor = on ? UIColor.label.withAlphaComponent(0.15) : .clear
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isEnabled, tracking == nil, let t = touches.first else { return }
        tracking = t
        setPressed(true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = tracking, touches.contains(t) else { return }
        setPressed(bounds.insetBy(dx: -slop, dy: -slop).contains(t.location(in: self)))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = tracking, touches.contains(t) else { return }
        tracking = nil
        setPressed(false)
        guard isEnabled, bounds.insetBy(dx: -slop, dy: -slop).contains(t.location(in: self)) else { return }
        action?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        tracking = nil
        setPressed(false)
    }
}

private struct TapTargetLayer: UIViewRepresentable {
    let cornerRadius: CGFloat
    let action: () -> Void

    func makeUIView(context: Context) -> TapTargetView {
        let v = TapTargetView()
        v.cornerRadius = cornerRadius
        return v
    }

    func updateUIView(_ v: TapTargetView, context: Context) {
        v.action = action
        v.cornerRadius = cornerRadius
        v.isEnabled = context.environment.isEnabled
    }
}

extension View {
    /// Makes this view tappable through UIKit. Use instead of `Button` anywhere inside the keyboard
    /// that is rebuilt while typing.
    func tapTarget(_ label: String, cornerRadius: CGFloat = 10,
                   hint: String? = nil, action: @escaping () -> Void) -> some View {
        overlay(TapTargetLayer(cornerRadius: cornerRadius, action: action))
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}
