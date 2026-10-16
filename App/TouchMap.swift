import SwiftUI

/// Hero illustration, drawn for the dark hero card: someone aiming at S keeps landing low and to the right,
/// and the keyboard learns that habit instead of typing whatever key sits under the finger.
/// Keys get a half-strength glass finish (soft fill, top sheen, bright rim); the fingerprint marks where taps land.
struct TouchMap: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private let rows = ["QWERT", "ASDFG", "ZXCV"]
    private let target = (row: 1, col: 1) // S
    /// Where the taps cluster, from the centre of S in key widths: the S/D/X corner, where a fixed keyboard types the wrong letter.
    private let landing = CGPoint(x: 0.78, y: 0.82)

    var body: some View {
        // One clock drives the whole sequence: fingerprint presses in, arrow draws to S, then a slow pulse.
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 10 : timeline.date.timeIntervalSince(start)
            Canvas { ctx, size in
                let g = Grid(size: size)
                drawKeys(ctx, g)
                drawTouch(ctx, g, t: t)
            }
        }
        .aspectRatio(1.56, contentMode: .fit)
        .onAppear { start = Date() }
        .accessibilityElement()
        .accessibilityLabel("Illustration: a fingerprint shows taps aimed at the S key landing below and to the right of it. The keyboard learns that pattern and still types S.")
    }

    private func drawKeys(_ ctx: GraphicsContext, _ g: Grid) {
        for (r, row) in rows.enumerated() {
            for (c, letter) in row.enumerated() {
                let rect = g.key(r, c)
                let isTarget = r == target.row && c == target.col
                let shape = Path(roundedRect: rect, cornerRadius: g.k * 0.2, style: .continuous)
                let top = CGPoint(x: rect.midX, y: rect.minY), bottom = CGPoint(x: rect.midX, y: rect.maxY)
                ctx.fill(shape, with: .linearGradient(
                    Gradient(colors: [.white.opacity(isTarget ? 0.42 : 0.2), .white.opacity(isTarget ? 0.22 : 0.06)]),
                    startPoint: top, endPoint: bottom))
                ctx.stroke(shape, with: .linearGradient(
                    Gradient(colors: [.white.opacity(isTarget ? 0.95 : 0.5), .white.opacity(isTarget ? 0.5 : 0.08)]),
                    startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)),
                    lineWidth: isTarget ? 1.5 : 1)
                ctx.draw(Text(String(letter)).font(.system(size: g.k * 0.36, weight: isTarget ? .semibold : .medium))
                            .foregroundColor(.white.opacity(isTarget ? 1 : 0.8)),
                         at: CGPoint(x: rect.midX, y: rect.midY))
            }
        }
    }

    private func drawTouch(_ ctx: GraphicsContext, _ g: Grid, t: Double) {
        let key = g.key(target.row, target.col)
        let centre = CGPoint(x: key.midX, y: key.midY)
        let p = CGPoint(x: centre.x + landing.x * g.k, y: centre.y + landing.y * g.k)
        let press = ease((t - 0.35) / 0.45)   // fingerprint presses in
        let draw = ease((t - 0.9) / 0.5)      // arrow draws back to S
        guard press > 0 else { return }
        let r = g.k * 0.32

        // Slow pulse once the sequence has played.
        if t > 1.5 {
            let phase = (t - 1.5).truncatingRemainder(dividingBy: 2.2) / 2.2
            let pr = r * (1 + phase * 0.7)
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - pr, y: p.y - pr, width: pr * 2, height: pr * 2)),
                       with: .color(Palette.touch.opacity((1 - phase) * 0.6)), lineWidth: 1.5)
        }

        var c = ctx
        c.opacity = press
        let s = 1.35 - 0.35 * press // lands from slightly above, like a fingertip
        let rr = r * s
        let disc = Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2))
        c.fill(disc, with: .radialGradient(Gradient(colors: [Palette.touch.opacity(0.45), Palette.touch.opacity(0)]),
                                           center: p, startRadius: 0, endRadius: rr * 1.6))
        // Glass disc under the print
        c.fill(disc, with: .linearGradient(Gradient(colors: [.white.opacity(0.92), .white.opacity(0.7)]),
                                           startPoint: CGPoint(x: p.x, y: p.y - rr), endPoint: CGPoint(x: p.x, y: p.y + rr)))
        c.stroke(disc, with: .color(.white), lineWidth: 1.25)
        c.draw(Text(Image(systemName: "touchid")).font(.system(size: rr * 1.15, weight: .regular))
                .foregroundColor(Palette.touch), at: p)

        guard draw > 0 else { return }
        // Arrow from the edge of the disc back to the key that was meant
        let angle = atan2(centre.y - p.y, centre.x - p.x)
        let from = CGPoint(x: p.x + cos(angle) * r * 1.08, y: p.y + sin(angle) * r * 1.08)
        let to = CGPoint(x: centre.x - cos(angle) * g.k * 0.1, y: centre.y - sin(angle) * g.k * 0.1)
        let tip = CGPoint(x: from.x + (to.x - from.x) * draw, y: from.y + (to.y - from.y) * draw)
        var arrow = Path()
        arrow.move(to: from)
        arrow.addLine(to: tip)
        for side in [-0.5, 0.5] {
            arrow.move(to: tip)
            arrow.addLine(to: CGPoint(x: tip.x - cos(angle + side) * g.k * 0.13 * draw,
                                      y: tip.y - sin(angle + side) * g.k * 0.13 * draw))
        }
        ctx.stroke(arrow, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    /// Ease-out on 0...1, clamped.
    private func ease(_ x: Double) -> Double {
        let v = min(max(x, 0), 1)
        return 1 - pow(1 - v, 3)
    }

    /// Staggered keyboard rows sized to fill the canvas.
    private struct Grid {
        let k: CGFloat, gap: CGFloat
        init(size: CGSize) {
            gap = size.width * 0.022
            k = min((size.width - gap * 4) / 5.3, (size.height - gap * 2) / 3.45)
        }
        func key(_ r: Int, _ c: Int) -> CGRect {
            CGRect(x: CGFloat(r) * k * 0.3 + CGFloat(c) * (k + gap), y: CGFloat(r) * (k * 1.15 + gap),
                   width: k, height: k * 1.15)
        }
    }
}

#Preview { TouchMap().padding(24).background(Hue.hero.gradient, in: RoundedRectangle(cornerRadius: 28)).padding() }
