import SwiftUI

/// Hero illustration: taps aimed at S keep landing low and to the right, and the keyboard learns that
/// pattern instead of typing whatever key sits under the finger. Mirrors the keyboard's "Show my touches".
struct TouchMap: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private let rows = ["QWERT", "ASDFG", "ZXCV"]
    private let target = (row: 1, col: 1) // S
    // Offsets from the centre of S, in key widths: they cluster on the S/D/X corner, where a fixed
    // keyboard would type the wrong letter. Hand-placed so they read as a habit, not noise.
    private let taps: [CGPoint] = [(0.52, 0.58), (0.70, 0.50), (0.58, 0.76), (0.80, 0.68),
                                   (0.64, 0.62), (0.46, 0.70), (0.74, 0.80)].map { CGPoint(x: $0.0, y: $0.1) }

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let g = Grid(size: size)
                for (r, row) in rows.enumerated() {
                    for (c, letter) in row.enumerated() {
                        let rect = g.key(r, c)
                        let isTarget = r == target.row && c == target.col
                        let shape = Path(roundedRect: rect, cornerRadius: g.k * 0.16)
                        ctx.fill(shape, with: .color(isTarget ? Palette.accent.opacity(0.12) : Palette.paper))
                        ctx.stroke(shape, with: .color(isTarget ? Palette.accent : Palette.line), lineWidth: isTarget ? 1.5 : 1)
                        ctx.draw(Text(String(letter)).font(.system(size: g.k * 0.36, weight: .medium))
                                    .foregroundColor(isTarget ? Palette.accent : Palette.inkSoft),
                                 at: CGPoint(x: rect.midX, y: rect.midY))
                    }
                }
            }
            Canvas { ctx, size in
                let g = Grid(size: size)
                let centre = CGPoint(x: g.key(target.row, target.col).midX, y: g.key(target.row, target.col).midY)
                let points = taps.map { CGPoint(x: centre.x + $0.x * g.k, y: centre.y + $0.y * g.k) }
                let mean = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                                   y: points.map(\.y).reduce(0, +) / CGFloat(points.count))

                // Learned spread
                let ellipse = CGRect(x: mean.x - g.k * 0.30, y: mean.y - g.k * 0.25, width: g.k * 0.60, height: g.k * 0.50)
                ctx.stroke(Path(ellipseIn: ellipse), with: .color(Palette.touch),
                           style: StrokeStyle(lineWidth: 1.25, dash: [4, 3]))
                for p in points {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - g.k * 0.055, y: p.y - g.k * 0.055,
                                                    width: g.k * 0.11, height: g.k * 0.11)), with: .color(Palette.touch))
                }

                // Arrow back to the key that was meant
                let angle = atan2(centre.y - mean.y, centre.x - mean.x)
                let tip = CGPoint(x: centre.x - cos(angle) * g.k * 0.12, y: centre.y - sin(angle) * g.k * 0.12)
                var arrow = Path()
                arrow.move(to: mean)
                arrow.addLine(to: tip)
                for side in [-0.5, 0.5] {
                    arrow.move(to: tip)
                    arrow.addLine(to: CGPoint(x: tip.x - cos(angle + side) * g.k * 0.13,
                                              y: tip.y - sin(angle + side) * g.k * 0.13))
                }
                ctx.stroke(arrow, with: .color(Palette.accent), style: StrokeStyle(lineWidth: 1.75, lineCap: .round))
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 4)
        }
        .aspectRatio(1.56, contentMode: .fit)
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(.easeOut(duration: 0.6).delay(0.25)) { shown = true } }
        }
        .accessibilityElement()
        .accessibilityLabel("Illustration: taps aimed at the S key land below and to the right of it. The keyboard learns that pattern and still types S.")
    }

    /// Staggered keyboard rows sized to fill the canvas.
    private struct Grid {
        let k: CGFloat, gap: CGFloat
        init(size: CGSize) {
            gap = size.width * 0.018
            k = min((size.width - gap * 4) / 5.3, (size.height - gap * 2) / 3.45)
        }
        func key(_ r: Int, _ c: Int) -> CGRect {
            CGRect(x: CGFloat(r) * k * 0.3 + CGFloat(c) * (k + gap), y: CGFloat(r) * (k * 1.15 + gap),
                   width: k, height: k * 1.15)
        }
    }
}

#Preview { TouchMap().padding(24).card().padding().background(Palette.paper) }
