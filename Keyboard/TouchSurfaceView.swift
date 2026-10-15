import UIKit
import TouchEngine

extension CGRect {
    init(_ r: Rect) { self.init(x: r.x, y: r.y, width: r.w, height: r.h) }
}

extension CGPoint {
    init(_ v: Vec2) { self.init(x: v.x, y: v.y) }
}

/// The key area. One view receives every touch and records its full path; keys are only drawn here.
/// Deciding which key was meant is the engine's job — not the view's hit-testing.
final class TouchSurfaceView: UIView {
    var layout: KeyboardLayout?
    var shift: ShiftState = .off
    var targetKeyID: String?
    var flashKeyID: String?
    var showTouches = false
    var trail: [TrailMark] = []
    var model: TouchModel?
    var candidates: [Candidate] = []

    var holdToDelete = true
    var onGesture: ((Gesture) -> Void)?
    var onGlobe: ((UIView, UIEvent) -> Void)?
    var onBackspaceRepeat: (() -> Void)?

    private var active: [ObjectIdentifier: [TouchSample]] = [:]
    private var globeTouches: Set<ObjectIdentifier> = []
    private var liveDots: [ObjectIdentifier: CGPoint] = [:]

    // Hold-to-delete: after 0.6 s on backspace, delete every 0.12 s until the finger lifts or slides away.
    private var holdTouch: ObjectIdentifier?
    private var holdStart = CGPoint.zero
    private var holdFired = false
    private var holdTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Touch capture

    private func sample(_ t: UITouch) -> TouchSample {
        let p = t.location(in: self)
        return TouchSample(Vec2(p.x, p.y), t.timestamp)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let id = ObjectIdentifier(t)
            let p = t.location(in: self)
            if layout?.key(at: Vec2(p.x, p.y)).kind == .nextKeyboard, let event {
                globeTouches.insert(id)
                onGlobe?(self, event) // system handles tap = next keyboard, long-press = list
                continue
            }
            active[id] = [sample(t)]
            liveDots[id] = p
            if holdToDelete, holdTouch == nil, layout?.key(at: Vec2(p.x, p.y)).kind == .backspace { startHold(id, at: p) }
        }
        setNeedsDisplay()
    }

    private func startHold(_ id: ObjectIdentifier, at p: CGPoint) {
        holdTouch = id
        holdStart = p
        holdFired = false
        holdTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            while !Task.isCancelled, let self {
                self.holdFired = true
                self.onBackspaceRepeat?()
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    private func endHold() {
        holdTask?.cancel()
        holdTask = nil
        holdTouch = nil
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let id = ObjectIdentifier(t)
            if globeTouches.contains(id) {
                if let event { onGlobe?(self, event) }
                continue
            }
            for c in event?.coalescedTouches(for: t) ?? [t] { active[id]?.append(sample(c)) }
            liveDots[id] = t.location(in: self)
            if id == holdTouch, !holdFired, let kw = layout?.keyWidth,
               hypot(t.location(in: self).x - holdStart.x, t.location(in: self).y - holdStart.y) > kw / 2 {
                endHold() // finger slid away: treat as a normal tap
            }
        }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let id = ObjectIdentifier(t)
            if globeTouches.remove(id) != nil {
                if let event { onGlobe?(self, event) }
                continue
            }
            liveDots[id] = nil
            if id == holdTouch {
                let fired = holdFired
                endHold()
                if fired { active[id] = nil; continue } // already deleted while held
            }
            guard var samples = active.removeValue(forKey: id) else { continue }
            samples.append(sample(t))
            onGesture?(Gesture(samples: samples))
        }
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let id = ObjectIdentifier(t)
            if globeTouches.remove(id) != nil, let event { onGlobe?(self, event) }
            if id == holdTouch { endHold() }
            active[id] = nil
            liveDots[id] = nil
        }
        setNeedsDisplay()
    }

    // MARK: Drawing

    private var highContrast: Bool { UIAccessibility.isDarkerSystemColorsEnabled }

    override func draw(_ rect: CGRect) {
        guard let layout else { return }
        let labelFont = UIFontMetrics(forTextStyle: .title2)
            .scaledFont(for: .systemFont(ofSize: 22), maximumPointSize: 30)
        let smallFont = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: .systemFont(ofSize: 15, weight: .medium), maximumPointSize: 20)

        for key in layout.keys {
            let r = CGRect(key.frame).insetBy(dx: 3, dy: 5)
            let path = UIBezierPath(roundedRect: r, cornerRadius: 7)
            let isTarget = key.id == targetKeyID
            let isFlash = key.id == flashKeyID
            let letterLike = key.isDecodable
            let fill: UIColor = isTarget ? .systemBlue
                : isFlash ? .systemGray2
                : letterLike ? UIColor { $0.userInterfaceStyle == .dark ? .systemGray2 : .white }
                : UIColor { $0.userInterfaceStyle == .dark ? .systemGray4 : .systemGray3 }
            fill.setFill()
            path.fill()
            if highContrast || isTarget {
                (isTarget ? UIColor.label : UIColor.label.withAlphaComponent(0.6)).setStroke()
                path.lineWidth = isTarget ? 3 : 1
                path.stroke()
            }
            drawLabel(for: key, in: r, color: isTarget ? .white : .label,
                      font: key.kind == .character ? labelFont : smallFont)
        }

        if showTouches { drawOverlay(layout) }

        UIColor.systemBlue.withAlphaComponent(0.35).setFill()
        for p in liveDots.values {
            UIBezierPath(ovalIn: CGRect(x: p.x - 14, y: p.y - 14, width: 28, height: 28)).fill()
        }
    }

    private func drawLabel(for key: Key, in r: CGRect, color: UIColor, font: UIFont) {
        let symbol: String?
        switch key.kind {
        case .shift: symbol = shift == .locked ? "capslock.fill" : shift == .once ? "shift.fill" : "shift"
        case .backspace: symbol = "delete.left"
        case .nextKeyboard: symbol = "globe"
        default: symbol = nil
        }
        if let symbol, let image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: font)) {
            let tinted = image.withTintColor(color, renderingMode: .alwaysOriginal)
            tinted.draw(at: CGPoint(x: r.midX - tinted.size.width / 2, y: r.midY - tinted.size.height / 2))
            return
        }
        let text: String
        if key.kind == .character, key.id.first?.isLetter == true {
            text = shift == .off ? key.id : key.id.uppercased()
        } else {
            text = key.label
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: CGPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: attrs)
    }

    /// Demo view: where the finger actually went, which point the model used, what it chose,
    /// and the learned touch pattern of the top two candidate keys.
    private func drawOverlay(_ layout: KeyboardLayout) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // Learned pattern (1-sigma ellipse around center + learned offset) for the last tap's top two keys.
        if let model {
            for cand in candidates.prefix(2) {
                guard let key = layout.key(id: cand.keyID) else { continue }
                let c = key.frame.center + model.offset(for: key)
                let e = model.cov(for: key).ellipse
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                ctx.rotate(by: e.angle)
                let oval = UIBezierPath(ovalIn: CGRect(x: -e.major, y: -e.minor, width: 2 * e.major, height: 2 * e.minor))
                oval.setLineDash([4, 3], count: 2, phase: 0)
                oval.lineWidth = 1.5
                UIColor.systemPurple.setStroke()
                oval.stroke()
                ctx.restoreGState()
                let mark = UIBezierPath(ovalIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6))
                UIColor.systemPurple.setFill()
                mark.fill()
            }
        }

        for (i, mark) in trail.enumerated() {
            let alpha = 0.35 + 0.65 * Double(i + 1) / Double(trail.count)
            guard let first = mark.path.first, let last = mark.path.last else { continue }

            // Movement path
            let line = UIBezierPath()
            line.move(to: CGPoint(first))
            mark.path.dropFirst().forEach { line.addLine(to: CGPoint($0)) }
            line.lineWidth = 2
            UIColor.systemGray.withAlphaComponent(alpha).setStroke()
            line.stroke()

            // Arrow from the point the model used to the key it chose
            if let target = mark.chosenCenter {
                let arrow = UIBezierPath()
                arrow.move(to: CGPoint(mark.usedPoint))
                arrow.addLine(to: CGPoint(target))
                arrow.lineWidth = 2
                UIColor.systemGreen.withAlphaComponent(alpha).setStroke()
                arrow.stroke()
            }

            // Touch-down (ring) and touch-up (dot). Orange = a fixed keyboard would have typed a different key.
            let color = mark.correctedByAdaptation ? UIColor.systemOrange : UIColor.systemBlue
            let ring = UIBezierPath(ovalIn: CGRect(x: first.x - 6, y: first.y - 6, width: 12, height: 12))
            ring.lineWidth = 2
            color.withAlphaComponent(alpha).setStroke()
            ring.stroke()
            color.withAlphaComponent(alpha).setFill()
            UIBezierPath(ovalIn: CGRect(x: last.x - 5, y: last.y - 5, width: 10, height: 10)).fill()
        }
    }
}
