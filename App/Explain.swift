import SwiftUI

/// Animated explanations of what the keyboard does, for the "How it works" and
/// "Compare keyboards" pages. Same player as the setup walkthroughs, but the pictures are
/// diagrams of the method rather than screens of an iPhone.
///
/// One synthetic typist runs through every picture: the same six taps, always landing low and
/// to the right, so each step clearly follows from the one before.

struct ExplainStep {
    let caption: String
    let diagram: Diagram
}

enum Diagram {
    /// A key lit up with a finger about to land off its centre.
    case target
    /// Where that person's taps for one key actually landed.
    case samples
    /// The offset and spread learned from those taps.
    case model
    /// A new tap scored against the keys around it.
    case scoring
    /// Two keys too close to call, offered as a choice.
    case choice
    /// The pattern moving as the person's touch changes.
    case adapting
    /// The same taps read by one of the three keyboards being compared.
    case reading(Reading)
    /// An illustration of what the built-in test reports.
    case results

    enum Reading { case standard, larger, adapted }
}

enum Explain {
    static let howItWorks: [ExplainStep] = [
        .init(caption: "We ask you to tap a key", diagram: .target),
        .init(caption: "Your taps land in your own spot", diagram: .samples),
        .init(caption: "We learn that spot and its spread", diagram: .model),
        .init(caption: "Each new tap is scored", diagram: .scoring),
        .init(caption: "Too close to call? You pick", diagram: .choice),
        .init(caption: "It keeps following your touch", diagram: .adapting),
    ]

    static let compare: [ExplainStep] = [
        .init(caption: "One set of taps, aimed at “hello”", diagram: .samples),
        .init(caption: "Standard keys read the key underneath", diagram: .reading(.standard)),
        .init(caption: "Larger keys help, but not always", diagram: .reading(.larger)),
        .init(caption: "Adapted keys use your own pattern", diagram: .reading(.adapted)),
        .init(caption: "You type the same phrases on all three", diagram: .results),
    ]
}

struct ExplainView: View {
    let steps: [ExplainStep]

    var body: some View {
        StepPlayer(captions: steps.map(\.caption)) { i in
            DiagramView(diagram: steps[i].diagram)
        }
    }
}

// MARK: - Drawing

private enum G {
    static let width: CGFloat = 330, height: CGFloat = 215
    static let rows = ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]

    static let keyW: CGFloat = 30, gap: CGFloat = 3
    static let standardH: CGFloat = 38, largeH: CGFloat = 52

    /// How far this person's finger lands from where they aimed, in points. Physical, so it does
    /// NOT shrink when the keys grow — which is exactly why taller keys help with some letters.
    static let drift = CGPoint(x: 15, y: 18)
    /// Taps are never identical, so each letter wobbles a little. Fixed per letter, so the picture
    /// is the same every time it plays.
    static let wobble: CGFloat = 4

    static func jitter(_ letter: Character) -> CGPoint {
        let n = Int(Character(String(letter).uppercased()).asciiValue ?? 65)
        return CGPoint(x: CGFloat((n * 37) % 11 - 5) / 5 * wobble,
                       y: CGFloat((n * 53) % 11 - 5) / 5 * wobble)
    }

    /// Keys sit at the bottom of the picture, so a taller row set still fits.
    static func rect(_ r: Int, _ c: Int, h: CGFloat = standardH) -> CGRect {
        let top = height - (3 * h + 2 * gap) - 6
        let rowShift = CGFloat(r) * keyW * 0.5
        return CGRect(x: rowShift + CGFloat(c) * (keyW + gap) + 4,
                      y: top + CGFloat(r) * (h + gap), width: keyW, height: h)
    }

    static func find(_ letter: Character) -> (Int, Int)? {
        let up = Character(String(letter).uppercased())
        for (r, row) in rows.enumerated() {
            if let i = row.firstIndex(of: up) { return (r, row.distance(from: row.startIndex, to: i)) }
        }
        return nil
    }

    /// Where the finger actually lands when aiming at `letter` on a keyboard with this key height.
    static func landing(_ letter: Character, h: CGFloat = standardH) -> CGPoint? {
        guard let (r, c) = find(letter) else { return nil }
        let m = rect(r, c, h: h), j = jitter(letter)
        return CGPoint(x: m.midX + drift.x + j.x, y: m.midY + drift.y + j.y)
    }

    /// What a plain keyboard of this key height makes of a touch: the key under it, else the nearest.
    static func read(_ p: CGPoint, h: CGFloat) -> Character {
        var best: (Character, CGFloat) = (" ", .greatestFiniteMagnitude)
        for (r, row) in rows.enumerated() {
            for (c, letter) in row.enumerated() {
                let rect = rect(r, c, h: h)
                if rect.contains(p) { return letter }
                let d = hypot(rect.midX - p.x, rect.midY - p.y)
                if d < best.1 { best = (letter, d) }
            }
        }
        return best.0
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

struct DiagramView: View {
    let diagram: Diagram

    /// The word the synthetic typist aims for in every picture.
    private static let aimed = "hello"

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in draw(ctx) }
                .frame(width: G.width, height: G.height)
            if case .target = diagram, let p = G.landing("S") {
                FingerDot(size: 40).position(p)
            }
        }
        .frame(width: G.width, height: G.height)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color(.separator), lineWidth: 0.5))
    }

    // MARK: Pieces

    private func keyboard(_ ctx: GraphicsContext, h: CGFloat = G.standardH,
                          highlight: Character? = nil, chosen: Set<Character> = []) {
        for (r, row) in G.rows.enumerated() {
            for (c, letter) in row.enumerated() {
                let rect = G.rect(r, c, h: h)
                let isTarget = highlight == letter
                let isChosen = chosen.contains(letter)
                let shape = Path(roundedRect: rect, cornerRadius: 6, style: .continuous)
                ctx.fill(shape, with: .color(isTarget ? Palette.accent
                                             : isChosen ? Palette.accent.opacity(0.25)
                                             : Color(.tertiarySystemFill)))
                ctx.stroke(shape, with: .color(isTarget ? Palette.accent : Color(.separator)), lineWidth: 1)
                ctx.draw(Text(String(letter))
                            .font(.system(size: 14, weight: isTarget || isChosen ? .bold : .regular))
                            .foregroundColor(isTarget ? .white : .primary),
                         at: rect.center)
            }
        }
    }

    private func taps(h: CGFloat = G.standardH) -> [(letter: Character, point: CGPoint)] {
        Self.aimed.compactMap { l in G.landing(l, h: h).map { (l, $0) } }
    }

    private func dot(_ ctx: GraphicsContext, _ p: CGPoint, r: CGFloat = 4.5, color: Color = Palette.touch) {
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                 with: .color(color))
    }

    private func arrow(_ ctx: GraphicsContext, from: CGPoint, to: CGPoint, color: Color) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        let a = atan2(to.y - from.y, to.x - from.x)
        var head = Path()
        for side in [-0.5, 0.5] {
            head.move(to: to)
            head.addLine(to: CGPoint(x: to.x - cos(a + side) * 8, y: to.y - sin(a + side) * 8))
        }
        ctx.stroke(head, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
    }

    private func caption(_ ctx: GraphicsContext, _ text: String, y: CGFloat) {
        ctx.draw(Text(text).font(.system(size: 11)).foregroundColor(.secondary),
                 at: CGPoint(x: G.width / 2, y: y))
    }

    /// Shows what a keyboard made of the taps, with the letters that are wrong picked out.
    private func typed(_ ctx: GraphicsContext, _ text: String) {
        let correct = text.lowercased() == Self.aimed
        var x = G.width / 2 - CGFloat(text.count) * 9
        for (i, ch) in text.lowercased().enumerated() {
            let wrong = Array(Self.aimed)[i] != ch
            ctx.draw(Text(String(ch))
                        .font(.system(size: 26, weight: .semibold, design: .monospaced))
                        .foregroundColor(wrong ? Palette.touch : .primary),
                     at: CGPoint(x: x, y: 26))
            x += 18
        }
        caption(ctx, correct ? "every letter right" : "the finger was read as the key underneath", y: 48)
    }

    // MARK: The pictures

    private func draw(_ ctx: GraphicsContext) {
        switch diagram {
        case .target:
            keyboard(ctx, highlight: "S")
            caption(ctx, "tap the key we light up", y: 30)

        case .samples:
            keyboard(ctx)
            for (letter, p) in taps() {
                if let (r, c) = G.find(letter) {
                    let m = G.rect(r, c).center
                    ctx.stroke(Path(ellipseIn: CGRect(x: m.x - 3.5, y: m.y - 3.5, width: 7, height: 7)),
                               with: .color(.secondary), lineWidth: 1)
                }
                dot(ctx, p)
            }
            caption(ctx, "● where the finger landed     ○ the key meant", y: 30)

        case .model:
            keyboard(ctx)
            guard let (r, c) = G.find("S"), let land = G.landing("S") else { return }
            let centre = G.rect(r, c).center
            let e = CGRect(x: land.x - 22, y: land.y - 16, width: 44, height: 32)
            ctx.fill(Path(ellipseIn: e), with: .color(Palette.touch.opacity(0.15)))
            ctx.stroke(Path(ellipseIn: e), with: .color(Palette.touch),
                       style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            dot(ctx, land)
            arrow(ctx, from: land, to: centre, color: Palette.accent)
            caption(ctx, "the offset we correct for, and how much you vary", y: 30)

        case .scoring:
            keyboard(ctx, chosen: ["S"])
            if let p = G.landing("S") { dot(ctx, p) }
            for (i, s) in [("S", 0.71), ("D", 0.22), ("X", 0.07)].enumerated() {
                let y = 20 + CGFloat(i) * 18
                ctx.draw(Text(s.0).font(.system(size: 13, weight: .semibold)), at: CGPoint(x: 22, y: y))
                ctx.fill(Path(roundedRect: CGRect(x: 36, y: y - 5, width: 160, height: 10), cornerRadius: 5),
                         with: .color(Color(.tertiarySystemFill)))
                ctx.fill(Path(roundedRect: CGRect(x: 36, y: y - 5, width: 160 * s.1, height: 10), cornerRadius: 5),
                         with: .color(i == 0 ? Palette.accent : Palette.accent.opacity(0.35)))
                ctx.draw(Text("\(Int(s.1 * 100))%").font(.system(size: 12).monospacedDigit())
                            .foregroundColor(.secondary),
                         at: CGPoint(x: 214, y: y))
            }

        case .choice:
            keyboard(ctx, chosen: ["S", "D"])
            if let p = G.landing("S") { dot(ctx, CGPoint(x: p.x + 10, y: p.y)) }
            for (i, letter) in ["S", "D"].enumerated() {
                let r = CGRect(x: 76 + CGFloat(i) * 96, y: 14, width: 86, height: 34)
                ctx.fill(Path(roundedRect: r, cornerRadius: 9, style: .continuous),
                         with: .color(i == 0 ? Palette.accent : Color(.tertiarySystemFill)))
                ctx.draw(Text(letter).font(.system(size: 18, weight: .bold))
                            .foregroundColor(i == 0 ? .white : .primary),
                         at: r.center)
            }
            caption(ctx, "one tap swaps it — nothing is guessed silently", y: 58)

        case .adapting:
            keyboard(ctx)
            guard let land = G.landing("S") else { return }
            let old = CGRect(x: land.x - 22, y: land.y - 16, width: 44, height: 32)
            let now = old.offsetBy(dx: 15, dy: 6)
            ctx.stroke(Path(ellipseIn: old), with: .color(.secondary.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            ctx.fill(Path(ellipseIn: now), with: .color(Palette.touch.opacity(0.15)))
            ctx.stroke(Path(ellipseIn: now), with: .color(Palette.touch), lineWidth: 1.5)
            arrow(ctx, from: old.center, to: now.center, color: Palette.accent)
            caption(ctx, "dashed: after calibration     solid: where you tap now", y: 30)

        case let .reading(mode):
            switch mode {
            case .standard:
                keyboard(ctx)
                let t = taps()
                for (_, p) in t { dot(ctx, p) }
                typed(ctx, String(t.map { G.read($0.point, h: G.standardH) }))
            case .larger:
                keyboard(ctx, h: G.largeH)
                let t = taps(h: G.largeH)
                for (_, p) in t { dot(ctx, p) }
                typed(ctx, String(t.map { G.read($0.point, h: G.largeH) }))
            case .adapted:
                keyboard(ctx, chosen: Set(Self.aimed.map { Character(String($0).uppercased()) }))
                for (letter, p) in taps() {
                    dot(ctx, p)
                    if let (r, c) = G.find(letter) {
                        arrow(ctx, from: p, to: G.rect(r, c).center, color: Palette.accent.opacity(0.75))
                    }
                }
                typed(ctx, Self.aimed)
            }

        case .results:
            ctx.draw(Text("Letters read correctly").font(.system(size: 14, weight: .semibold)),
                     at: CGPoint(x: G.width / 2, y: 22))
            for (i, row) in [("Standard", 0.62, Color(.systemGray)),
                             ("Larger", 0.79, Color(.systemGray2)),
                             ("Adapted", 0.94, Palette.accent)].enumerated() {
                let y = 64 + CGFloat(i) * 42
                ctx.draw(Text(row.0).font(.system(size: 13)).foregroundColor(.secondary),
                         at: CGPoint(x: 48, y: y))
                ctx.fill(Path(roundedRect: CGRect(x: 92, y: y - 10, width: 170, height: 20), cornerRadius: 10),
                         with: .color(Color(.tertiarySystemFill)))
                ctx.fill(Path(roundedRect: CGRect(x: 92, y: y - 10, width: 170 * row.1, height: 20), cornerRadius: 10),
                         with: .color(row.2))
                ctx.draw(Text("\(Int(row.1 * 100))%").font(.system(size: 13).monospacedDigit()),
                         at: CGPoint(x: 288, y: y))
            }
            caption(ctx, "An example of the report. Your own run decides the numbers.", y: 196)
        }
    }
}

#Preview("How it works") { ExplainView(steps: Explain.howItWorks).padding() }
#Preview("Compare") { ExplainView(steps: Explain.compare).padding() }
