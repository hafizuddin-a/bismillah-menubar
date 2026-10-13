// gen_strokes.swift
// Turns an Arabic string + a system font into (1) a filled outline path and
// (2) an ordered list of "pen strokes" (centerlines + widths + timings) that,
// used as animated stroke masks over the outline, make the text look hand-written.
//
//   swiftc -O gen_strokes.swift -o gen_strokes && ./gen_strokes "Geeza Pro" out_dir
import Foundation
import AppKit
import CoreText
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - config
let text = "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ"
let fontFamily = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Geeza Pro"
let outDir = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "."
let fontSize: CGFloat = 320
let margin = 12
let outWidth = 1000.0                  // output units: outline is scaled to this width
let targetSeconds = 4.9                // time at which the last stroke ends
let chunkPx = 130.0                     // max raster length of one mask chunk
let wordGapPx = 0.30 * Double(fontSize)
let markMaxPx = 0.28 * Double(fontSize)

// MARK: - shaping
let nsFont = NSFont(name: fontFamily, size: fontSize)
    ?? NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: fontFamily]), size: fontSize)
    ?? NSFont.systemFont(ofSize: fontSize)
let attr = NSAttributedString(string: text, attributes: [.font: nsFont])
let line = CTLineCreateWithAttributedString(attr)
let outline = CGMutablePath()
for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let n = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: n)
    var pos = [CGPoint](repeating: .zero, count: n)
    CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: 0), &pos)
    let attrs = CTRunGetAttributes(run) as NSDictionary
    let runFont = attrs[kCTFontAttributeName as String] as! CTFont
    for i in 0..<n {
        if let gp = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
            outline.addPath(gp, transform: CGAffineTransform(translationX: pos[i].x, y: pos[i].y))
        }
    }
}
let bbox = outline.boundingBoxOfPath
let k = outWidth / Double(bbox.width)               // raster px -> output units
let W = Int(ceil(bbox.width)) + 2 * margin
let H = Int(ceil(bbox.height)) + 2 * margin
let viewH = Double(bbox.height) * k
print("font:", nsFont.fontName, "bbox:", bbox.size, "raster:", W, "x", H, "k:", k)

// MARK: - rasterize
var gray = [UInt8](repeating: 0, count: W * H)
gray.withUnsafeMutableBytes { raw in
    let ctx = CGContext(data: raw.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.translateBy(x: CGFloat(margin) - bbox.minX, y: CGFloat(margin) - bbox.minY)
    ctx.setFillColor(gray: 1, alpha: 1)
    ctx.addPath(outline)
    ctx.fillPath()
}
var fg = [UInt8](repeating: 0, count: W * H)
for i in 0..<(W * H) where gray[i] > 127 { fg[i] = 1 }

// raster pixel (x,row) centre -> output coordinates (y down, like SVG)
func toOut(_ x: Double, _ r: Double) -> (Double, Double) {
    ((x - Double(margin)) * k, (r - Double(margin) - (Double(H - 2 * margin) - Double(bbox.height))) * k)
}

// MARK: - distance transform (chamfer)
var dt = [Float](repeating: 0, count: W * H)
do {
    let big: Float = 1e6
    for i in 0..<(W * H) { dt[i] = fg[i] == 1 ? big : 0 }
    let d1: Float = 1, d2: Float = 1.41421356
    for y in 1..<(H - 1) { for x in 1..<(W - 1) {
        let i = y * W + x
        if dt[i] == 0 { continue }
        dt[i] = min(dt[i], dt[i - 1] + d1, dt[i - W] + d1, dt[i - W - 1] + d2, dt[i - W + 1] + d2)
    } }
    for y in stride(from: H - 2, through: 1, by: -1) { for x in stride(from: W - 2, through: 1, by: -1) {
        let i = y * W + x
        if dt[i] == 0 { continue }
        dt[i] = min(dt[i], dt[i + 1] + d1, dt[i + W] + d1, dt[i + W + 1] + d2, dt[i + W - 1] + d2)
    } }
}

// MARK: - connected components (8-neighbour)
var label = [Int32](repeating: -1, count: W * H)
struct Comp { var id = 0; var minX = Int.max, maxX = 0, minY = Int.max, maxY = 0; var area = 0; var isMark = false
    var cx: Double { Double(minX + maxX) / 2 } }
var comps: [Comp] = []
let nb8 = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
for s in 0..<(W * H) where fg[s] == 1 && label[s] < 0 {
    var c = Comp(); c.id = comps.count
    var stack = [s]; label[s] = Int32(c.id)
    while let i = stack.popLast() {
        let x = i % W, y = i / W
        c.minX = min(c.minX, x); c.maxX = max(c.maxX, x); c.minY = min(c.minY, y); c.maxY = max(c.maxY, y); c.area += 1
        for (dx, dy) in nb8 {
            let j = (y + dy) * W + (x + dx)
            if fg[j] == 1 && label[j] < 0 { label[j] = Int32(c.id); stack.append(j) }
        }
    }
    c.isMark = Double(max(c.maxX - c.minX, c.maxY - c.minY)) < markMaxPx
    comps.append(c)
}
print("components:", comps.count, "marks:", comps.filter { $0.isMark }.count)

// MARK: - thinning (Guo-Hall)
var sk = fg
do {
    var del: [Int] = []
    var changed = true
    while changed {
        changed = false
        for sub in 0..<2 {
            del.removeAll(keepingCapacity: true)
            for y in 1..<(H - 1) {
                let row = y * W
                for x in 1..<(W - 1) {
                    let i = row + x
                    if sk[i] == 0 { continue }
                    let p2 = Int(sk[i - W]), p3 = Int(sk[i - W + 1]), p4 = Int(sk[i + 1]), p5 = Int(sk[i + W + 1])
                    let p6 = Int(sk[i + W]), p7 = Int(sk[i + W - 1]), p8 = Int(sk[i - 1]), p9 = Int(sk[i - W - 1])
                    let C = ((1 - p2) & (p3 | p4)) + ((1 - p4) & (p5 | p6)) + ((1 - p6) & (p7 | p8)) + ((1 - p8) & (p9 | p2))
                    let N1 = (p9 | p2) + (p3 | p4) + (p5 | p6) + (p7 | p8)
                    let N2 = (p2 | p3) + (p4 | p5) + (p6 | p7) + (p8 | p9)
                    let N = min(N1, N2)
                    if C == 1 && N >= 2 && N <= 3 {
                        let m = sub == 0 ? ((p6 | p7 | (1 - p9)) & p8) : ((p2 | p3 | (1 - p5)) & p4)
                        if m == 0 { del.append(i) }
                    }
                }
            }
            if !del.isEmpty { changed = true; for i in del { sk[i] = 0 } }
        }
    }
}
// drop redundant staircase corners
for _ in 0..<2 {
    for y in 1..<(H - 1) { for x in 1..<(W - 1) {
        let i = y * W + x
        if sk[i] == 0 { continue }
        var ns: [(Int, Int)] = []
        for (dx, dy) in nb8 where sk[(y + dy) * W + (x + dx)] == 1 { ns.append((dx, dy)) }
        if ns.count == 2 && abs(ns[0].0 - ns[1].0) <= 1 && abs(ns[0].1 - ns[1].1) <= 1 { sk[i] = 0 }
    } }
}
func degree(_ i: Int) -> Int {
    var d = 0
    for (dx, dy) in nb8 where sk[i + dy * W + dx] == 1 { d += 1 }
    return d
}
print("skeleton px:", sk.reduce(0) { $0 + Int($1) })

// MARK: - heap + dijkstra helpers
struct Heap {
    var a: [(Float, Int32)] = []
    mutating func push(_ v: (Float, Int32)) {
        a.append(v); var i = a.count - 1
        while i > 0 { let p = (i - 1) / 2; if a[p].0 <= a[i].0 { break }; a.swapAt(p, i); i = p }
    }
    mutating func pop() -> (Float, Int32)? {
        if a.isEmpty { return nil }
        let top = a[0]; let last = a.removeLast()
        if !a.isEmpty {
            a[0] = last; var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1; var m = i
                if l < a.count && a[l].0 < a[m].0 { m = l }
                if r < a.count && a[r].0 < a[m].0 { m = r }
                if m == i { break }; a.swapAt(m, i); i = m
            }
        }
        return top
    }
}
var state = [UInt8](repeating: 0, count: W * H)      // 0 none, 1 skeleton unvisited, 2 consumed
for i in 0..<(W * H) where sk[i] == 1 { state[i] = 1 }
var distBuf = [Float](repeating: .infinity, count: W * H)
var prevBuf = [Int32](repeating: -1, count: W * H)

/// Longest geodesic path starting at `start` through state==1 pixels. Returns pixel indices start...end.
func longestPath(from start: Int) -> [Int] {
    var touched: [Int] = []
    var heap = Heap()
    distBuf[start] = 0; prevBuf[start] = -1; touched.append(start); heap.push((0, Int32(start)))
    var far = start
    while let (d, ii) = heap.pop() {
        let i = Int(ii)
        if d > distBuf[i] { continue }
        if d > distBuf[far] || far == start { far = i }
        let x = i % W, y = i / W
        for (dx, dy) in nb8 {
            let j = (y + dy) * W + (x + dx)
            if state[j] != 1 { continue }
            let nd = d + ((dx != 0 && dy != 0) ? 1.41421356 : 1)
            if nd < distBuf[j] {
                if distBuf[j] == .infinity { touched.append(j) }
                distBuf[j] = nd; prevBuf[j] = Int32(i); heap.push((nd, Int32(j)))
            }
        }
    }
    var path: [Int] = []
    var c = far
    while c != -1 { path.append(c); c = Int(prevBuf[c]) }
    for t in touched { distBuf[t] = .infinity; prevBuf[t] = -1 }
    return path.reversed()
}
func markComponent(from start: Int) {          // consume everything reachable through state==1
    var stack = [start]; state[start] = 2
    while let i = stack.popLast() {
        let x = i % W, y = i / W
        for (dx, dy) in nb8 { let j = (y + dy) * W + (x + dx); if state[j] == 1 { state[j] = 2; stack.append(j) } }
    }
}

// MARK: - peeling into ordered pieces
struct Piece { var pts: [CGPoint]; var radius: Double; var newPen: Bool; var isMark: Bool; var lenPx: Double; var gap: Double = 0 }
var pieces: [Piece] = []
var nextGap = 0.0

func polyLen(_ p: [CGPoint]) -> Double {
    var l = 0.0
    for i in 1..<max(p.count, 1) { l += hypot(Double(p[i].x - p[i - 1].x), Double(p[i].y - p[i - 1].y)) }
    return l
}
func rdp(_ p: [CGPoint], _ eps: Double) -> [CGPoint] {
    if p.count < 3 { return p }
    let a = p[0], b = p[p.count - 1]
    var md = 0.0, mi = 0
    let dx = Double(b.x - a.x), dy = Double(b.y - a.y), L = hypot(dx, dy)
    for i in 1..<(p.count - 1) {
        let d = L < 1e-9 ? hypot(Double(p[i].x - a.x), Double(p[i].y - a.y))
                         : abs(dy * Double(p[i].x - a.x) - dx * Double(p[i].y - a.y)) / L
        if d > md { md = d; mi = i }
    }
    if md > eps { return Array(rdp(Array(p[0...mi]), eps).dropLast()) + rdp(Array(p[mi...]), eps) }
    return [a, b]
}
func pt(_ i: Int) -> CGPoint { CGPoint(x: Double(i % W) + 0.5, y: Double(i / W) + 0.5) }

/// Emit a path (pixel indices) as chunks, splitting also at `splitAt` indices (children get emitted between).
func emit(path: [Int], children: [(Int, [Int])], newPen: Bool, isMark: Bool, start: Int, end: Int, first: Bool) {
    // emit path[start...end] split into chunks
    var i0 = start; var firstChunk = first
    var acc = 0.0; var rmax: Float = 0
    var lastI = start
    func flush(_ upto: Int) {
        if upto <= i0 { return }
        let pts = path[i0...upto].map(pt)
        var r = 0.0
        for q in path[i0...upto] { r = max(r, Double(dt[q])) }
        let np = firstChunk && newPen
        pieces.append(Piece(pts: rdp(pts, 1.6), radius: r, newPen: np, isMark: isMark, lenPx: polyLen(pts), gap: np ? nextGap : 0))
        if np { nextGap = 0.015 }
        firstChunk = false; i0 = upto; acc = 0; rmax = 0
    }
    var j = start
    while j < end {
        j += 1
        acc += hypot(Double(pt(path[j]).x - pt(path[j - 1]).x), Double(pt(path[j]).y - pt(path[j - 1]).y))
        rmax = max(rmax, dt[path[j]]); lastI = j
        if acc >= chunkPx { flush(j) }
    }
    flush(end)
    _ = rmax; _ = lastI
}

func peel(start: Int, isMark: Bool, newPen: Bool) {
    var path = longestPath(from: start)
    let r0 = Double(dt[start])
    if path.count < 2 && !isMark { markComponent(from: start); return }
    if !newPen && polyLen(path.map(pt)) < max(6, 1.3 * r0) { markComponent(from: start); return }
    for p in path { state[p] = 2 }
    // find attach points of leftover pieces: neighbours of path pixels with state==1
    var children: [(Int, Int)] = []               // (index along path, child start pixel)
    for (idx, p) in path.enumerated() {
        let x = p % W, y = p / W
        for (dx, dy) in nb8 {
            let j = (y + dy) * W + (x + dx)
            if state[j] == 1 {
                children.append((idx, j))
                markFlood(j, tag: 3)             // reserve the component so it is only attached once
            }
        }
    }
    // re-open reserved comps (state 3 -> 1) so child peels can run
    for (_, c) in children { reopen(c) }
    // emit main path in sections between child attach indices
    var cur = 0
    var firstSection = true
    var sortedKids = children.sorted { $0.0 < $1.0 }
    if path.count == 1 { path.append(path[0]) }
    for kid in sortedKids {
        if kid.0 > cur {
            emit(path: path, children: [], newPen: newPen, isMark: isMark, start: cur, end: kid.0, first: firstSection)
            firstSection = false; cur = kid.0
        }
        peel(start: kid.1, isMark: isMark, newPen: false)
    }
    if cur < path.count - 1 || firstSection {
        emit(path: path, children: [], newPen: newPen, isMark: isMark, start: cur, end: max(path.count - 1, cur), first: firstSection)
    }
    sortedKids.removeAll()
}
func markFlood(_ s: Int, tag: UInt8) {
    var stack = [s]; state[s] = tag
    while let i = stack.popLast() {
        let x = i % W, y = i / W
        for (dx, dy) in nb8 { let j = (y + dy) * W + (x + dx); if state[j] == 1 { state[j] = tag; stack.append(j) } }
    }
}
func reopen(_ s: Int) {
    // state 3 region -> 1 (flood over 3s)
    var stack = [s]; state[s] = 1
    while let i = stack.popLast() {
        let x = i % W, y = i / W
        for (dx, dy) in nb8 { let j = (y + dy) * W + (x + dx); if state[j] == 3 { state[j] = 1; stack.append(j) } }
    }
}

// MARK: - driver: order components like a scribe (right-to-left, words, then marks)
func startPixel(of comp: Comp) -> Int? {
    var best: Int? = nil; var bestEnd = false
    for y in comp.minY...comp.maxY { for x in comp.minX...comp.maxX {
        let i = y * W + x
        if state[i] != 1 || Int(label[i]) != comp.id { continue }
        let isEnd = degree(i) == 1
        if best == nil { best = i; bestEnd = isEnd; continue }
        let bx = best! % W
        if (isEnd && !bestEnd) || (isEnd == bestEnd && x > bx) { best = i; bestEnd = isEnd }
    } }
    return best
}
let bodies = comps.filter { !$0.isMark }.sorted { $0.maxX > $1.maxX }
var words: [[Comp]] = []
var curMin = Int.max
for b in bodies {
    if words.isEmpty || Double(curMin - b.maxX) > wordGapPx { words.append([b]); curMin = b.minX }
    else { words[words.count - 1].append(b); curMin = min(curMin, b.minX) }
}
print("words:", words.count, words.map { $0.count })
let wordRanges = words.map { w in (w.map { $0.minX }.min()!, w.map { $0.maxX }.max()!) }
var marksOf = [[Comp]](repeating: [], count: words.count)
for m in comps where m.isMark {
    var bi = 0; var bd = Double.infinity
    for (wi, r) in wordRanges.enumerated() {
        let d = m.cx < Double(r.0) ? Double(r.0) - m.cx : (m.cx > Double(r.1) ? m.cx - Double(r.1) : 0)
        if d < bd { bd = d; bi = wi }
    }
    marksOf[bi].append(m)
}
for wi in 0..<words.count {
    nextGap = wi == 0 ? 0 : 0.09
    for b in words[wi] {
        if let s = startPixel(of: b) { peel(start: s, isMark: false, newPen: true) }
    }
    nextGap = 0.05
    for m in marksOf[wi].sorted(by: { $0.cx > $1.cx }) {
        if let s = startPixel(of: m) { peel(start: s, isMark: true, newPen: true) }
        nextGap = 0.015
    }
}
print("pieces:", pieces.count)

// MARK: - timings
let minLenPx = 2.0
let t_start = 0.05
let sumGaps = pieces.reduce(0.0) { $0 + $1.gap }
func minDur(_ p: Piece) -> Double { p.isMark ? 0.018 : 0.010 }
var speed = 400.0
for _ in 0..<40 {                       // fixed point: min durations make the end time non-linear
    var t = t_start + sumGaps
    for p in pieces { t += max(max(p.lenPx, minLenPx) * k / speed, minDur(p)) }
    speed *= t / targetSeconds
}
struct Stroke { var d: String; var w: Double; var len: Double; var t0: Double; var dur: Double; var mark: Bool; var pts: [(Double, Double)] }
var strokes: [Stroke] = []
func f0(_ v: Double) -> String { String(Int(v.rounded())) }
func f1(_ v: Double) -> String { let s = String(format: "%.1f", v); return s.hasSuffix(".0") ? String(s.dropLast(2)) : s }
var clock = t_start
for p in pieces {
    var pts = p.pts
    if polyLen(pts) < minLenPx {          // dots: give them a tiny horizontal extent so a dash can animate
        let c = pts[0]; pts = [CGPoint(x: c.x + 1, y: c.y), CGPoint(x: c.x - 1, y: c.y)]
    }
    let len = polyLen(pts) * k
    let dur = max(len / speed, minDur(p))
    clock += p.gap
    let wPx = 2 * p.radius * 1.3 + 3
    let d = "M" + pts.map { q -> String in let o = toOut(Double(q.x), Double(q.y)); return f0(o.0) + " " + f0(o.1) }.joined(separator: " ")
    strokes.append(Stroke(d: d, w: wPx * k, len: len, t0: clock, dur: dur, mark: p.isMark, pts: pts.map { toOut(Double($0.x), Double($0.y)) }))
    clock += dur
}
let endT = clock
print(String(format: "strokes: %d  pen end: %.2fs  speed: %.0f u/s", strokes.count, endT, speed))

// MARK: - outline as SVG path
var od = ""
func ox(_ p: CGPoint) -> String { f1(Double(p.x - bbox.minX) * k) + " " + f1(Double(bbox.maxY - p.y) * k) }
outline.applyWithBlock { e in
    let el = e.pointee; let p = el.points
    switch el.type {
    case .moveToPoint: od += "M" + ox(p[0])
    case .addLineToPoint: od += "L" + ox(p[0])
    case .addQuadCurveToPoint: od += "Q" + ox(p[0]) + " " + ox(p[1])
    case .addCurveToPoint: od += "C" + ox(p[0]) + " " + ox(p[1]) + " " + ox(p[2])
    case .closeSubpath: od += "Z"
    @unknown default: break
    }
}

// MARK: - coverage check + debug image
var cover = [UInt8](repeating: 0, count: W * H)
cover.withUnsafeMutableBytes { raw in
    let ctx = CGContext(data: raw.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)
    ctx.setStrokeColor(gray: 1, alpha: 1); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    for p in pieces {
        ctx.setLineWidth(CGFloat(2 * p.radius * 1.3 + 3))
        ctx.beginPath(); ctx.move(to: p.pts[0]); for q in p.pts.dropFirst() { ctx.addLine(to: q) }
        if p.pts.count == 1 { ctx.addLine(to: CGPoint(x: p.pts[0].x + 0.1, y: p.pts[0].y)) }
        ctx.strokePath()
    }
}
var unc = 0, tot = 0
var rgba = [UInt8](repeating: 0, count: W * H * 4)
for i in 0..<(W * H) {
    var c: (UInt8, UInt8, UInt8) = (0, 0, 0)
    if fg[i] == 1 { tot += 1; if cover[i] > 127 { c = (90, 90, 90) } else { unc += 1; c = (255, 40, 40) } }
    else if cover[i] > 127 { c = (25, 25, 60) }
    rgba[i * 4] = c.0; rgba[i * 4 + 1] = c.1; rgba[i * 4 + 2] = c.2; rgba[i * 4 + 3] = 255
}
print(String(format: "uncovered glyph px: %d of %d (%.2f%%)", unc, tot, 100 * Double(unc) / Double(tot)))
rgba.withUnsafeMutableBytes { raw in
    let ctx = CGContext(data: raw.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)
    ctx.setLineWidth(2.5); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    for (n, p) in pieces.enumerated() {
        let hue = CGFloat(n) / CGFloat(max(pieces.count, 1)) * 0.85
        let col = NSColor(hue: hue, saturation: 1, brightness: 1, alpha: 1).cgColor
        ctx.setStrokeColor(col)
        ctx.beginPath(); ctx.move(to: p.pts[0]); for q in p.pts.dropFirst() { ctx.addLine(to: q) }
        ctx.strokePath()
        if p.newPen { ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fillEllipse(in: CGRect(x: p.pts[0].x - 5, y: p.pts[0].y - 5, width: 10, height: 10)) }
    }
    if let img = ctx.makeImage() {
        let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outDir + "/debug.png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dst, img, nil); CGImageDestinationFinalize(dst)
    }
}

// MARK: - write JSON
var json = "{\"w\":\(f1(outWidth)),\"h\":\(f1(viewH)),\"end\":\(String(format: "%.2f", endT)),\"outline\":\"\(od)\",\"strokes\":[\n"
json += strokes.map { s in
    "{\"d\":\"\(s.d)\",\"w\":\(f0(max(s.w, 1))),\"len\":\(f0(s.len)),\"t0\":\(String(format: "%.3f", s.t0)),\"dur\":\(String(format: "%.3f", s.dur)),\"m\":\(s.mark ? 1 : 0)}"
}.joined(separator: ",\n")
json += "\n]}\n"
try! json.write(toFile: outDir + "/strokes.json", atomically: true, encoding: .utf8)
print("outline chars:", od.count, " json bytes:", json.utf8.count)


// MARK: - frame sheet (simulate the reveal at a few times)
let sheetTimes: [Double] = [0.7, 1.4, 2.1, 2.8, 3.5, 4.2]
let half = 2
let sw = W / half, sh = H / half
var sheet = [UInt8](repeating: 0, count: sw * sh * sheetTimes.count * 4)
for (fi, T) in sheetTimes.enumerated() {
    var m = [UInt8](repeating: 0, count: W * H)
    m.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)
        ctx.setStrokeColor(gray: 1, alpha: 1); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        for (n, p) in pieces.enumerated() {
            let st = strokes[n]
            let f = min(max((T - st.t0) / st.dur, 0), 1)
            if f <= 0 { continue }
            var pts = p.pts
            if polyLen(pts) < minLenPx { let c = pts[0]; pts = [CGPoint(x: c.x + 1, y: c.y), CGPoint(x: c.x - 1, y: c.y)] }
            let target = polyLen(pts) * f
            var acc = 0.0
            ctx.setLineWidth(CGFloat(2 * p.radius * 1.3 + 3))
            ctx.beginPath(); ctx.move(to: pts[0])
            for i in 1..<pts.count {
                let seg = hypot(Double(pts[i].x - pts[i - 1].x), Double(pts[i].y - pts[i - 1].y))
                if acc + seg >= target {
                    let u = seg < 1e-9 ? 0 : (target - acc) / seg
                    ctx.addLine(to: CGPoint(x: Double(pts[i - 1].x) + Double(pts[i].x - pts[i - 1].x) * u, y: Double(pts[i - 1].y) + Double(pts[i].y - pts[i - 1].y) * u)); break
                }
                acc += seg; ctx.addLine(to: pts[i])
            }
            ctx.strokePath()
        }
    }
    for y in 0..<sh { for x in 0..<sw {
        let i = (y * half) * W + x * half
        let v: UInt8 = (fg[i] == 1 && m[i] > 127) ? 255 : (fg[i] == 1 ? 40 : 0)
        let o = ((fi * sh + y) * sw + x) * 4
        sheet[o] = v; sheet[o + 1] = v; sheet[o + 2] = v; sheet[o + 3] = 255
    } }
}
sheet.withUnsafeMutableBytes { raw in
    let ctx = CGContext(data: raw.baseAddress, width: sw, height: sh * sheetTimes.count, bitsPerComponent: 8, bytesPerRow: sw * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if let img = ctx.makeImage() {
        let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outDir + "/frames.png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dst, img, nil); CGImageDestinationFinalize(dst)
    }
}


// MARK: - Swift data file for the macOS app
var src = "// Generated by tools/gen_strokes.swift (font: \(nsFont.fontName)). Do not edit.\n"
src += "// Coordinates are in a \(f1(outWidth)) x \(f1(viewH)) box, y pointing down.\n\n"
src += "struct PenStroke {\n    let points: [Double]   // x0, y0, x1, y1, ...\n    let width: Double\n    let start: Double\n    let duration: Double\n}\n\n"
src += "enum BismillahData {\n    static let width: Double = \(f1(outWidth))\n    static let height: Double = \(f1(viewH))\n    static let penEnd: Double = \(String(format: "%.2f", endT))\n\n"
src += "    static let outline: String = \"\(od)\"\n\n    static let strokes: [PenStroke] = [\n"
for st in strokes {
    let pts = st.pts.map { f1($0.0) + ", " + f1($0.1) }.joined(separator: ", ")
    src += "        PenStroke(points: [\(pts)], width: \(f1(max(st.w, 1))), start: \(String(format: "%.3f", st.t0)), duration: \(String(format: "%.3f", st.dur))),\n"
}
src += "    ]\n}\n"
try! src.write(toFile: outDir + "/BismillahData.swift", atomically: true, encoding: .utf8)
