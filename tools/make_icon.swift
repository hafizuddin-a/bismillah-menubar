// make_icon.swift — draws the app icon at every size macOS wants into an .iconset folder.
//   swiftc -O tools/make_icon.swift -o /tmp/make_icon && /tmp/make_icon Bismillah.iconset
// (tools/make_icon.sh wraps this and runs iconutil.)
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Bismillah.iconset"
let text = "بسم الله"                       // plain letters, no harakat

/// Apple's icon grid: a 824 pt body centred on a 1024 pt canvas, corners closer to a superellipse than a circle.
func squircle(half: CGFloat, center: CGPoint, exponent n: Double = 5) -> CGPath {
    let path = CGMutablePath()
    let steps = 720
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = Double(half) * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = Double(half) * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        let p = CGPoint(x: center.x + CGFloat(x), y: center.y + CGFloat(y))
        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    path.closeSubpath()
    return path
}

func render(pixels px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let k = CGFloat(px) / 1024
    ctx.scaleBy(x: k, y: k)
    let centre = CGPoint(x: 512, y: 512)
    let body = squircle(half: 412, center: centre)

    // soft drop shadow under the body
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: CGColor(gray: 0, alpha: 0.45))
    ctx.addPath(body)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // black body with the faintest lift at the top so it doesn't read as a flat hole
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    let colors = [CGColor(gray: 0.17, alpha: 1), CGColor(gray: 0.0, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 0.75])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    // hairline edge
    ctx.addPath(squircle(half: 411, center: centre))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10))
    ctx.setLineWidth(2)
    ctx.strokePath()

    // the words, sized to ~64% of the body width and centred on their ink bounds
    // Geeza Pro, the same face as the popup; it puts the usual shadda over الله by itself
    let font = NSFont(name: "GeezaPro", size: 100) ?? NSFont.systemFont(ofSize: 100)
    let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
    let line = CTLineCreateWithAttributedString(attr)
    let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    let scale = (824 * 0.64) / ink.width
    ctx.saveGState()
    ctx.translateBy(x: 512 - ink.midX * scale, y: 512 - ink.midY * scale)
    ctx.scaleBy(x: scale, y: scale)
    ctx.textPosition = .zero
    CTLineDraw(line, ctx)
    ctx.restoreGState()

    return ctx.makeImage()!
}

func write(_ image: CGImage, to name: String) {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name) as CFURL
    let dst = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, image, nil)
    CGImageDestinationFinalize(dst)
}

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    write(render(pixels: base), to: "icon_\(base)x\(base).png")
    write(render(pixels: base * 2), to: "icon_\(base)x\(base)@2x.png")
}
print("wrote iconset to \(outDir)")
