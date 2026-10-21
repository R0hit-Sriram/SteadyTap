import Foundation

public enum KeyKind: String, Codable, Sendable {
    case character, space, shift, backspace, returnKey, pageSwitch, nextKeyboard
}

public enum KeyboardPage: String, Codable, Sendable {
    case letters, symbols
}

public struct Key: Equatable, Sendable {
    /// Stable id: the character itself for character keys ("a", ",", "?"), otherwise a name ("space", "shift", …).
    public let id: String
    public let label: String
    public let kind: KeyKind
    /// Key area in keyboard coordinates.
    public let frame: Rect
    public let row: Int
    /// Screen region (row × left/middle/right third). Used to share learned offsets between nearby keys.
    public let region: Int

    /// Character and space keys are interpreted by the touch model; the rest are plain hit-tested buttons.
    public var isDecodable: Bool { kind == .character || kind == .space }

    /// Where on this key a tap at `p` was aimed: the center, or for a wide key (space) the nearest point
    /// along its middle, so a tap near the end of the space bar isn't "far" from it.
    public func aim(for p: Vec2, keyWidth kw: Double) -> Vec2 {
        let c = frame.center, half = max(0, (frame.w - kw) / 2)
        return Vec2(min(max(p.x, c.x - half), c.x + half), c.y)
    }

    /// Text this key types, before shift is applied.
    public var output: String? {
        switch kind {
        case .character: return id
        case .space: return " "
        case .returnKey: return "\n"
        default: return nil
        }
    }
}

public struct KeyboardLayout: Sendable {
    public let page: KeyboardPage
    public let keys: [Key]
    public let width: Double
    public let rowHeight: Double
    /// Width of one letter key (a tenth of the keyboard).
    public var keyWidth: Double { width / 10 }
    public var height: Double { rowHeight * 4 }
    public var decodableKeys: [Key] { keys.filter(\.isDecodable) }

    public func key(id: String) -> Key? { keys.first { $0.id == id } }

    /// The FIXED-keyboard reading: the key whose area contains the point, else the nearest key center.
    public func key(at p: Vec2) -> Key {
        if let k = keys.first(where: { $0.frame.contains(p) }) { return k }
        return keys.min { ($0.frame.center - p).length < ($1.frame.center - p).length }!
    }

    public static func make(page: KeyboardPage, width: Double, rowHeight: Double, showNextKeyboard: Bool) -> KeyboardLayout {
        let kw = width / 10
        var keys: [Key] = []

        func add(_ id: String, _ label: String, _ kind: KeyKind, row: Int, x: Double, w: Double) {
            let frame = Rect(x: x, y: Double(row) * rowHeight, w: w, h: rowHeight)
            let zone = min(2, max(0, Int(frame.center.x / (width / 3))))
            keys.append(Key(id: id, label: label, kind: kind, frame: frame, row: row, region: row * 3 + zone))
        }
        func chars(_ s: String, row: Int, startX: Double, w: Double) {
            for (i, c) in s.enumerated() {
                add(String(c), page == .letters ? String(c).uppercased() : String(c), .character, row: row, x: startX + Double(i) * w, w: w)
            }
        }

        switch page {
        case .letters:
            chars("qwertyuiop", row: 0, startX: 0, w: kw)
            chars("asdfghjkl", row: 1, startX: kw / 2, w: kw)
            add("shift", "⇧", .shift, row: 2, x: 0, w: 1.5 * kw)
            chars("zxcvbnm", row: 2, startX: 1.5 * kw, w: kw)
            add("backspace", "⌫", .backspace, row: 2, x: 8.5 * kw, w: 1.5 * kw)
        case .symbols:
            chars("1234567890", row: 0, startX: 0, w: kw)
            chars("-/:;()$&@\"", row: 1, startX: 0, w: kw)
            chars(".,?!'", row: 2, startX: 1.5 * kw, w: 1.4 * kw)
            add("backspace", "⌫", .backspace, row: 2, x: 8.5 * kw, w: 1.5 * kw)
        }

        // Bottom row: [123/ABC] [🌐] [,] [space……] [.] [return]
        // Side keys are trimmed so space gets the room: 4 key widths with 🌐, 5 without.
        var bottom: [(String, String, KeyKind, Double)] = [("page", page == .letters ? "123" : "ABC", .pageSwitch, 1.25)]
        if showNextKeyboard { bottom.append(("globe", "🌐", .nextKeyboard, 1)) }
        if page == .letters { bottom.append((",", ",", .character, 1)) }
        bottom.append(("space", "space", .space, 0))
        if page == .letters { bottom.append((".", ".", .character, 1)) }
        bottom.append(("return", "return", .returnKey, 1.75))
        let spaceUnits = 10 - bottom.reduce(0) { $0 + $1.3 }
        var x = 0.0
        for (id, label, kind, units) in bottom {
            let w = (kind == .space ? spaceUnits : units) * kw
            add(id, label, kind, row: 3, x: x, w: w)
            x += w
        }
        return KeyboardLayout(page: page, keys: keys, width: width, rowHeight: rowHeight)
    }
}
