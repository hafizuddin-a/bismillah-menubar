import CoreGraphics
import Foundation

/// Minimal SVG path parser: absolute M, L, Q, C, Z (with implicit lineto after M).
/// That is all the outline generator emits, so there is no need for a full parser.
enum SVGPath {
    private enum Token {
        case command(Character)
        case number(CGFloat)
    }

    static func parse(_ d: String, transform: CGAffineTransform = .identity) -> CGPath {
        let tokens = tokenize(d)
        let path = CGMutablePath()
        var command: Character = "M"
        var i = 0

        func take(_ n: Int) -> [CGFloat]? {
            var values: [CGFloat] = []
            var j = i
            while values.count < n, j < tokens.count, case .number(let v) = tokens[j] {
                values.append(v)
                j += 1
            }
            guard values.count == n else { return nil }
            i = j
            return values
        }

        func point(_ v: [CGFloat], _ k: Int) -> CGPoint {
            CGPoint(x: v[k], y: v[k + 1]).applying(transform)
        }

        while i < tokens.count {
            if case .command(let c) = tokens[i] {
                command = c
                i += 1
                if c == "Z" { path.closeSubpath() }
                continue
            }
            switch command {
            case "M":
                guard let v = take(2) else { return path }
                path.move(to: point(v, 0))
                command = "L"                       // extra pairs after M are lineto
            case "L":
                guard let v = take(2) else { return path }
                path.addLine(to: point(v, 0))
            case "Q":
                guard let v = take(4) else { return path }
                path.addQuadCurve(to: point(v, 2), control: point(v, 0))
            case "C":
                guard let v = take(6) else { return path }
                path.addCurve(to: point(v, 4), control1: point(v, 0), control2: point(v, 2))
            default:
                i += 1
            }
        }
        return path
    }

    private static func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        func flush() {
            if !current.isEmpty, let v = Double(current) { tokens.append(.number(CGFloat(v))) }
            current = ""
        }
        for ch in d {
            if ch.isLetter {
                flush()
                tokens.append(.command(ch))
            } else if ch == " " || ch == "," {
                flush()
            } else if ch == "-" {
                flush()
                current = "-"
            } else {
                current.append(ch)
            }
        }
        flush()
        return tokens
    }
}
