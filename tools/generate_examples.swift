#!/usr/bin/env swift
//
//  generate_examples.swift — example artwork generator
//
//  Draws placeholder coloring sheets (black line art on white, closed
//  regions so bucket fill stays bounded) and colorful store covers for
//  every asset manifest.json references.
//
//  Output goes to art/ (gitignored — plaintext artwork must never be
//  committed to this public repo). Encrypt results into assets/ with
//  tools/encrypt.swift.
//
//  Usage: swift tools/generate_examples.swift   (run from the repo root)
//

import CoreGraphics
import Foundation
import ImageIO

// MARK: - Canvas

final class Canvas {
    let ctx: CGContext
    let w: CGFloat
    let h: CGFloat
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    init(width: Int, height: Int) {
        w = CGFloat(width)
        h = CGFloat(height)
        ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: 0, space: Self.srgb,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Top-left origin so scenes read like screen coordinates.
        ctx.translateBy(x: 0, y: h)
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(rgb(1, 1, 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
    }

    func stroke(_ path: CGPath, width: CGFloat = 16, color: CGColor = rgb(0, 0, 0)) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.addPath(path)
        ctx.strokePath()
    }

    func fill(_ path: CGPath, color: CGColor) {
        ctx.setFillColor(color)
        ctx.addPath(path)
        ctx.fillPath()
    }

    /// White interior + black outline: lets shapes overlap cleanly in line art.
    func shape(_ path: CGPath, lineWidth: CGFloat = 16, fillColor: CGColor = rgb(1, 1, 1)) {
        fill(path, color: fillColor)
        stroke(path, width: lineWidth)
    }

    func gradient(_ top: CGColor, _ bottom: CGColor) {
        let g = CGGradient(colorsSpace: Self.srgb, colors: [top, bottom] as CFArray,
                           locations: [0, 1])!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: h), options: [])
    }

    func save(to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let image = ctx.makeImage()!
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: Canvas.srgb, components: [r, g, b, a])!
}

// MARK: - Path builders

func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r), transform: nil)
}

func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry), transform: nil)
}

func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, corner: CGFloat = 0) -> CGPath {
    let r = CGRect(x: x, y: y, width: w, height: h)
    return corner > 0 ? CGPath(roundedRect: r, cornerWidth: corner, cornerHeight: corner, transform: nil)
                      : CGPath(rect: r, transform: nil)
}

func polygon(_ points: [(CGFloat, CGFloat)], closed: Bool = true) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: points[0].0, y: points[0].1))
    for pt in points.dropFirst() { p.addLine(to: CGPoint(x: pt.0, y: pt.1)) }
    if closed { p.closeSubpath() }
    return p
}

func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> CGPath {
    polygon([(x1, y1), (x2, y2)], closed: false)
}

func star(_ cx: CGFloat, _ cy: CGFloat, outer: CGFloat, inner: CGFloat, points: Int = 5) -> CGPath {
    var pts: [(CGFloat, CGFloat)] = []
    for i in 0..<(points * 2) {
        let r = i.isMultiple(of: 2) ? outer : inner
        let a = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
        pts.append((cx + r * cos(a), cy + r * sin(a)))
    }
    return polygon(pts)
}

func heart(_ cx: CGFloat, _ cy: CGFloat, width: CGFloat) -> CGPath {
    let s = width / 32
    let ox = cx - 16 * s, oy = cy - 14.8 * s
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
    let p = CGMutablePath()
    p.move(to: pt(23.6, 0))
    p.addCurve(to: pt(16, 5.6), control1: pt(20.2, 0), control2: pt(17.3, 2.7))
    p.addCurve(to: pt(8.4, 0), control1: pt(14.7, 2.7), control2: pt(11.8, 0))
    p.addCurve(to: pt(0, 8.4), control1: pt(3.8, 0), control2: pt(0, 3.8))
    p.addCurve(to: pt(16, 29.6), control1: pt(0, 17.8), control2: pt(9.5, 20.3))
    p.addCurve(to: pt(32, 8.4), control1: pt(22.1, 20.3), control2: pt(32, 17.5))
    p.addCurve(to: pt(23.6, 0), control1: pt(32, 3.8), control2: pt(28.2, 0))
    return p
}

/// Horizontal wavy line: one bump per `wavelength`, alternating up/down.
func wave(_ x1: CGFloat, _ x2: CGFloat, _ y: CGFloat, amp: CGFloat, wavelength: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x1, y: y))
    var x = x1
    var up = true
    while x < x2 {
        let next = min(x + wavelength, x2)
        p.addQuadCurve(to: CGPoint(x: next, y: y),
                       control: CGPoint(x: (x + next) / 2, y: y + (up ? -amp : amp)))
        up.toggle()
        x = next
    }
    return p
}

/// Puffy cloud: closed run of bumps over a flat base.
func cloud(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let h = w * 0.36
    p.move(to: CGPoint(x: cx - w / 2, y: cy + h / 2))
    p.addQuadCurve(to: CGPoint(x: cx - w * 0.42, y: cy - h * 0.2),
                   control: CGPoint(x: cx - w * 0.62, y: cy - h * 0.15))
    p.addQuadCurve(to: CGPoint(x: cx - w * 0.1, y: cy - h * 0.55),
                   control: CGPoint(x: cx - w * 0.38, y: cy - h * 0.85))
    p.addQuadCurve(to: CGPoint(x: cx + w * 0.22, y: cy - h * 0.35),
                   control: CGPoint(x: cx + w * 0.08, y: cy - h * 0.85))
    p.addQuadCurve(to: CGPoint(x: cx + w / 2, y: cy + h / 2),
                   control: CGPoint(x: cx + w * 0.62, y: cy - h * 0.35))
    p.closeSubpath()
    return p
}

func sun(_ c: Canvas, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, lineWidth: CGFloat = 16) {
    for i in 0..<8 {
        let a = CGFloat(i) * .pi / 4
        c.stroke(line(cx + cos(a) * r * 1.3, cy + sin(a) * r * 1.3,
                      cx + cos(a) * r * 1.75, cy + sin(a) * r * 1.75), width: lineWidth)
    }
    c.shape(circle(cx, cy, r), lineWidth: lineWidth)
}

func flower(_ c: Canvas, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, stemTo groundY: CGFloat) {
    c.stroke(line(cx, cy + r, cx, groundY))
    let leafY = (cy + r + groundY) / 2
    c.shape(ellipse(cx + r * 0.55, leafY, r * 0.55, r * 0.26))
    for i in 0..<6 {
        let a = CGFloat(i) * .pi / 3 - .pi / 2
        c.shape(circle(cx + cos(a) * r * 0.72, cy + sin(a) * r * 0.72, r * 0.42))
    }
    c.shape(circle(cx, cy, r * 0.4))
}

func spiral(_ cx: CGFloat, _ cy: CGFloat, turns: CGFloat, maxR: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let steps = Int(turns * 48)
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let a = t * turns * 2 * .pi
        let r = maxR * t
        let pt = CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r)
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    return p
}

// MARK: - Sheets (1536×2048 portrait, line art)

typealias Draw = (Canvas) -> Void
let W: CGFloat = 1536, H: CGFloat = 2048

var sheets: [String: Draw] = [:]

// ---- Free drop 2026-07 ----

sheets["free/2026-07/buzzy-meadow"] = { c in
    sun(c, 260, 300, 130)
    c.shape(cloud(1150, 330, 420))
    // Bee
    let bx: CGFloat = 768, by: CGFloat = 850
    c.shape(ellipse(bx - 170, by - 190, 150, 90))       // left wing
    c.shape(ellipse(bx + 170, by - 190, 150, 90))       // right wing
    c.shape(ellipse(bx, by, 260, 180))                  // body
    c.stroke(line(bx - 90, by - 172, bx - 90, by + 172))
    c.stroke(line(bx + 20, by - 178, bx + 20, by + 178))
    c.stroke(line(bx + 120, by - 152, bx + 120, by + 152))
    c.shape(circle(bx - 205, by - 60, 16), fillColor: rgb(0, 0, 0)) // eye
    c.stroke(line(bx - 150, by - 165, bx - 220, by - 260))
    c.shape(circle(bx - 230, by - 275, 22))
    // Meadow
    c.stroke(wave(0, W, 1650, amp: 40, wavelength: 380))
    flower(c, 380, 1420, 110, stemTo: 1660)
    flower(c, 768, 1500, 90, stemTo: 1690)
    flower(c, 1160, 1400, 120, stemTo: 1650)
}

sheets["free/2026-07/picnic-day"] = { c in
    sun(c, 1270, 300, 130)
    c.shape(cloud(400, 320, 430))
    // Blanket
    let blanket = polygon([(280, 1350), (1256, 1350), (1436, 1900), (100, 1900)])
    c.shape(blanket)
    for t in stride(from: 0.25, to: 1.0, by: 0.25) {
        let tt = CGFloat(t)
        c.stroke(line(280 + 976 * tt, 1350, 100 + 1336 * tt, 1900))
    }
    c.stroke(line(235, 1490, 1300, 1490))
    c.stroke(line(170, 1690, 1370, 1690))
    // Basket
    c.shape(rect(560, 980, 420, 300, corner: 40))
    c.stroke(line(560, 1080, 980, 1080))
    c.stroke(line(700, 1000, 700, 1270))
    c.stroke(line(840, 1000, 840, 1270))
    let handle = CGMutablePath()
    handle.move(to: CGPoint(x: 620, y: 985))
    handle.addQuadCurve(to: CGPoint(x: 920, y: 985), control: CGPoint(x: 770, y: 700))
    c.stroke(handle)
    // Apple
    c.shape(circle(1180, 1180, 105))
    c.stroke(line(1180, 1075, 1180, 1000))
    c.shape(ellipse(1250, 1010, 70, 32))
}

// ---- Free drop 2026-08 ----

sheets["free/2026-08/sandcastle"] = { c in
    sun(c, 270, 300, 130)
    // Towers
    c.shape(rect(300, 1050, 260, 600))
    c.shape(rect(976, 1050, 260, 600))
    c.shape(rect(560, 900, 416, 750))
    // Crenellations
    for x: CGFloat in [300, 976] {
        c.shape(rect(x - 20, 970, 80, 80))
        c.shape(rect(x + 90, 970, 80, 80))
        c.shape(rect(x + 200, 970, 80, 80))
    }
    c.shape(rect(600, 820, 90, 80))
    c.shape(rect(723, 820, 90, 80))
    c.shape(rect(846, 820, 90, 80))
    // Flag
    c.stroke(line(768, 820, 768, 600))
    c.shape(polygon([(768, 600), (960, 660), (768, 720)]))
    // Door
    let door = CGMutablePath()
    door.move(to: CGPoint(x: 690, y: 1650))
    door.addLine(to: CGPoint(x: 690, y: 1450))
    door.addQuadCurve(to: CGPoint(x: 846, y: 1450), control: CGPoint(x: 768, y: 1320))
    door.addLine(to: CGPoint(x: 846, y: 1650))
    c.stroke(door)
    // Beach + waves
    c.stroke(wave(0, W, 1700, amp: 36, wavelength: 320))
    c.stroke(wave(120, 620, 1850, amp: 30, wavelength: 250))
    c.stroke(wave(900, 1420, 1870, amp: 30, wavelength: 250))
}

sheets["free/2026-08/tide-pool"] = { c in
    c.shape(ellipse(768, 1250, 620, 460))
    c.shape(ellipse(768, 1250, 500, 350))
    // Starfish
    c.shape(star(560, 1220, outer: 190, inner: 85))
    // Crab
    let cx: CGFloat = 1010, cy: CGFloat = 1330
    c.shape(ellipse(cx, cy, 150, 105))
    c.shape(circle(cx - 190, cy - 120, 55))
    c.shape(circle(cx + 190, cy - 120, 55))
    c.stroke(line(cx - 110, cy - 55, cx - 165, cy - 100))
    c.stroke(line(cx + 110, cy - 55, cx + 165, cy - 100))
    c.shape(circle(cx - 55, cy - 30, 14), fillColor: rgb(0, 0, 0))
    c.shape(circle(cx + 55, cy - 30, 14), fillColor: rgb(0, 0, 0))
    // Bubbles + shells
    c.shape(circle(430, 620, 60))
    c.shape(circle(560, 500, 40))
    c.shape(circle(1080, 560, 52))
    for (sx, sy) in [(340.0, 1800.0), (1180.0, 1780.0)] {
        let shell = CGMutablePath()
        shell.move(to: CGPoint(x: sx - 90, y: sy))
        shell.addQuadCurve(to: CGPoint(x: sx + 90, y: sy), control: CGPoint(x: sx, y: sy - 170))
        shell.closeSubpath()
        c.shape(shell)
        c.stroke(line(sx, sy, sx - 40, sy - 95), width: 12)
        c.stroke(line(sx, sy, sx + 40, sy - 95), width: 12)
    }
}

// ---- Ocean pack ----

sheets["packs/ocean/OceanSheet1"] = { c in
    // Big friendly fish
    let fx: CGFloat = 700, fy: CGFloat = 900
    c.shape(ellipse(fx, fy, 420, 260))
    c.shape(polygon([(fx + 380, fy), (fx + 640, fy - 200), (fx + 640, fy + 200)]))
    let gill = CGMutablePath()
    gill.move(to: CGPoint(x: fx - 140, y: fy - 180))
    gill.addQuadCurve(to: CGPoint(x: fx - 140, y: fy + 180), control: CGPoint(x: fx - 260, y: fy))
    c.stroke(gill)
    c.shape(ellipse(fx + 60, fy - 20, 130, 70))          // side fin
    c.shape(circle(fx - 250, fy - 70, 34), fillColor: rgb(0, 0, 0))
    // Bubbles
    c.shape(circle(330, 450, 55))
    c.shape(circle(450, 330, 38))
    c.shape(circle(250, 300, 30))
    // Seaweed + floor
    c.stroke(wave(0, W, 1800, amp: 36, wavelength: 300))
    for x: CGFloat in [280, 420, 1140, 1290] {
        let weed = CGMutablePath()
        weed.move(to: CGPoint(x: x, y: 1800))
        weed.addQuadCurve(to: CGPoint(x: x - 40, y: 1500), control: CGPoint(x: x + 90, y: 1650))
        weed.addQuadCurve(to: CGPoint(x: x + 10, y: 1280), control: CGPoint(x: x - 110, y: 1380))
        c.stroke(weed)
    }
    c.shape(star(820, 1780, outer: 110, inner: 50))
}

sheets["packs/ocean/OceanSheet2"] = { c in
    // Whale
    let wx: CGFloat = 730, wy: CGFloat = 1150
    let body = CGMutablePath()
    body.move(to: CGPoint(x: wx - 520, y: wy + 60))
    body.addQuadCurve(to: CGPoint(x: wx + 350, y: wy - 280), control: CGPoint(x: wx - 380, y: wy - 460))
    body.addQuadCurve(to: CGPoint(x: wx + 470, y: wy + 120), control: CGPoint(x: wx + 560, y: wy - 120))
    body.addLine(to: CGPoint(x: wx - 520, y: wy + 120))
    body.closeSubpath()
    c.shape(body)
    // Tail
    c.shape(polygon([(wx + 430, wy - 40), (wx + 660, wy - 260), (wx + 700, wy - 40)]))
    c.shape(circle(wx - 360, wy - 90, 30), fillColor: rgb(0, 0, 0))
    let smile = CGMutablePath()
    smile.move(to: CGPoint(x: wx - 500, y: wy + 10))
    smile.addQuadCurve(to: CGPoint(x: wx - 250, y: wy + 30), control: CGPoint(x: wx - 380, y: wy + 90))
    c.stroke(smile)
    // Spout
    let spout1 = CGMutablePath()
    spout1.move(to: CGPoint(x: wx - 200, y: wy - 350))
    spout1.addQuadCurve(to: CGPoint(x: wx - 330, y: wy - 560), control: CGPoint(x: wx - 200, y: wy - 520))
    c.stroke(spout1)
    let spout2 = CGMutablePath()
    spout2.move(to: CGPoint(x: wx - 200, y: wy - 350))
    spout2.addQuadCurve(to: CGPoint(x: wx - 70, y: wy - 560), control: CGPoint(x: wx - 200, y: wy - 520))
    c.stroke(spout2)
    c.shape(circle(wx - 330, wy - 620, 44))
    c.shape(circle(wx - 70, wy - 620, 44))
    // Sea
    c.stroke(wave(0, W, 1600, amp: 42, wavelength: 340))
    c.stroke(wave(100, 700, 1750, amp: 34, wavelength: 280))
    c.stroke(wave(850, 1450, 1770, amp: 34, wavelength: 280))
}

// ---- Sunset pack ----

sheets["packs/sunset/SunsetSheet1"] = { c in
    // Horizon sun with rays
    let cy: CGFloat = 1150
    let half = CGMutablePath()
    half.move(to: CGPoint(x: 768 - 330, y: cy))
    half.addQuadCurve(to: CGPoint(x: 768 + 330, y: cy), control: CGPoint(x: 768, y: cy - 640))
    half.closeSubpath()
    c.shape(half)
    for i in 1...5 {
        let a = CGFloat(i) * .pi / 6
        c.stroke(line(768 - cos(a) * 420, cy - sin(a) * 420,
                      768 - cos(a) * 560, cy - sin(a) * 560))
    }
    // Rolling hills
    let hillL = CGMutablePath()
    hillL.move(to: CGPoint(x: 0, y: cy))
    hillL.addQuadCurve(to: CGPoint(x: 900, y: cy + 500), control: CGPoint(x: 420, y: cy + 60))
    hillL.addLine(to: CGPoint(x: 0, y: cy + 500))
    hillL.closeSubpath()
    c.shape(hillL)
    let hillR = CGMutablePath()
    hillR.move(to: CGPoint(x: W, y: cy))
    hillR.addQuadCurve(to: CGPoint(x: 500, y: cy + 700), control: CGPoint(x: 1050, y: cy + 160))
    hillR.addLine(to: CGPoint(x: W, y: cy + 700))
    hillR.closeSubpath()
    c.shape(hillR)
    c.stroke(line(0, cy, 768 - 330, cy))
    c.stroke(line(768 + 330, cy, W, cy))
    // Birds
    for (bx, by) in [(380.0, 420.0), (620.0, 320.0), (1120.0, 460.0)] {
        let bird = CGMutablePath()
        bird.move(to: CGPoint(x: bx - 90, y: by))
        bird.addQuadCurve(to: CGPoint(x: bx, y: by), control: CGPoint(x: bx - 45, y: by - 70))
        bird.addQuadCurve(to: CGPoint(x: bx + 90, y: by), control: CGPoint(x: bx + 45, y: by - 70))
        c.stroke(bird, width: 14)
    }
}

sheets["packs/sunset/SunsetSheet2"] = { c in
    sun(c, 1280, 280, 110)
    // Balloon
    c.shape(circle(700, 780, 420))
    for dx: CGFloat in [-210, 0, 210] {
        c.shape(ellipse(700 + dx / 1.6, 780, abs(dx) < 1 ? 150 : 240, 420))
    }
    // Ropes + basket
    c.stroke(line(560, 1170, 620, 1420))
    c.stroke(line(840, 1170, 780, 1420))
    c.shape(rect(590, 1420, 220, 180, corner: 30))
    c.stroke(line(590, 1480, 810, 1480))
    // Clouds
    c.shape(cloud(320, 1450, 380))
    c.shape(cloud(1180, 1700, 460))
}

// ---- Forest pack ----

sheets["packs/forest/ForestSheet1"] = { c in
    // Canopy: overlapping bumps drawn as one blob
    let canopy = CGMutablePath()
    canopy.move(to: CGPoint(x: 350, y: 950))
    canopy.addQuadCurve(to: CGPoint(x: 420, y: 560), control: CGPoint(x: 210, y: 690))
    canopy.addQuadCurve(to: CGPoint(x: 790, y: 380), control: CGPoint(x: 520, y: 330))
    canopy.addQuadCurve(to: CGPoint(x: 1130, y: 580), control: CGPoint(x: 1060, y: 340))
    canopy.addQuadCurve(to: CGPoint(x: 1180, y: 950), control: CGPoint(x: 1340, y: 720))
    canopy.addQuadCurve(to: CGPoint(x: 350, y: 950), control: CGPoint(x: 768, y: 1080))
    canopy.closeSubpath()
    c.shape(canopy)
    // Trunk
    c.shape(polygon([(680, 940), (640, 1600), (900, 1600), (860, 940)]))
    let knot = CGMutablePath()
    knot.move(to: CGPoint(x: 720, y: 1150))
    knot.addQuadCurve(to: CGPoint(x: 720, y: 1310), control: CGPoint(x: 810, y: 1230))
    c.stroke(knot)
    // Ground + mushrooms
    c.stroke(wave(0, W, 1640, amp: 34, wavelength: 340))
    for (mx, scale) in [(330.0, 1.0), (1200.0, 1.25)] {
        let s = CGFloat(scale)
        let cap = CGMutablePath()
        cap.move(to: CGPoint(x: mx - 150 * s, y: 1560))
        cap.addQuadCurve(to: CGPoint(x: mx + 150 * s, y: 1560), control: CGPoint(x: mx, y: 1280))
        cap.closeSubpath()
        c.shape(rect(mx - 55 * s, 1560, 110 * s, 160 * s, corner: 30))
        c.shape(cap)
        c.shape(circle(mx - 60 * s, 1480, 26))
        c.shape(circle(mx + 45 * s, 1440, 30))
    }
}

sheets["packs/forest/ForestSheet2"] = { c in
    // Branch
    c.stroke(line(80, 1500, 1456, 1420), width: 26)
    c.shape(ellipse(1280, 1360, 130, 55))
    c.shape(ellipse(240, 1560, 130, 55))
    // Owl
    let ox: CGFloat = 760, oy: CGFloat = 1010
    c.shape(ellipse(ox, oy, 330, 430))
    // Ear tufts
    c.shape(polygon([(ox - 260, oy - 300), (ox - 300, oy - 500), (ox - 120, oy - 400)]))
    c.shape(polygon([(ox + 260, oy - 300), (ox + 300, oy - 500), (ox + 120, oy - 400)]))
    // Eyes
    c.shape(circle(ox - 140, oy - 200, 130))
    c.shape(circle(ox + 140, oy - 200, 130))
    c.shape(circle(ox - 140, oy - 200, 55), fillColor: rgb(0, 0, 0))
    c.shape(circle(ox + 140, oy - 200, 55), fillColor: rgb(0, 0, 0))
    // Beak + belly feathers
    c.shape(polygon([(ox - 55, oy - 60), (ox + 55, oy - 60), (ox, oy + 60)]))
    for row in 0..<3 {
        let y = oy + 150 + CGFloat(row) * 90
        for col in 0..<(4 - row) {
            let x = ox - CGFloat(3 - row) * 55 + CGFloat(col) * 110
            let feather = CGMutablePath()
            feather.move(to: CGPoint(x: x - 45, y: y))
            feather.addQuadCurve(to: CGPoint(x: x + 45, y: y), control: CGPoint(x: x, y: y + 70))
            c.stroke(feather, width: 12)
        }
    }
    // Moon + stars
    c.shape(circle(280, 340, 120))
    c.shape(star(1200, 300, outer: 70, inner: 30))
    c.shape(star(1050, 520, outer: 50, inner: 22))
}

// ---- First Shapes pack (minimal: few, huge, simple) ----

sheets["packs/firstshapes/FirstShapesSheet1"] = { c in
    c.shape(rect(400, 1000, 736, 700), lineWidth: 20)                       // house
    c.shape(polygon([(330, 1000), (768, 560), (1206, 1000)]), lineWidth: 20) // roof
    c.shape(rect(660, 1350, 216, 350), lineWidth: 20)                        // door
    sun(c, 280, 300, 120, lineWidth: 20)
}

sheets["packs/firstshapes/FirstShapesSheet2"] = { c in
    c.shape(star(768, 950, outer: 520, inner: 230), lineWidth: 20)
    c.shape(star(330, 1700, outer: 140, inner: 62), lineWidth: 20)
    c.shape(star(1200, 1720, outer: 170, inner: 75), lineWidth: 20)
}

sheets["packs/firstshapes/FirstShapesSheet3"] = { c in
    c.shape(heart(768, 900, width: 1000), lineWidth: 20)
    c.shape(heart(360, 1700, width: 300), lineWidth: 20)
    c.shape(heart(1180, 1720, width: 360), lineWidth: 20)
}

sheets["packs/firstshapes/FirstShapesSheet4"] = { c in
    let bx: CGFloat = 768, by: CGFloat = 1024
    c.shape(ellipse(bx - 330, by - 320, 300, 260), lineWidth: 20) // wings
    c.shape(ellipse(bx + 330, by - 320, 300, 260), lineWidth: 20)
    c.shape(ellipse(bx - 300, by + 260, 250, 210), lineWidth: 20)
    c.shape(ellipse(bx + 300, by + 260, 250, 210), lineWidth: 20)
    c.shape(ellipse(bx, by, 110, 420), lineWidth: 20)             // body
    c.stroke(line(bx - 40, by - 400, bx - 130, by - 580), width: 20)
    c.stroke(line(bx + 40, by - 400, bx + 130, by - 580), width: 20)
    c.shape(circle(bx - 150, by - 610, 34), lineWidth: 20)
    c.shape(circle(bx + 150, by - 610, 34), lineWidth: 20)
}

// ---- Busy Bugs pack ----

sheets["packs/busybugs/BusyBugsSheet1"] = { c in
    // Ladybug
    let lx: CGFloat = 768, ly: CGFloat = 1050
    c.shape(circle(lx, ly, 460))
    let head = CGMutablePath()
    head.move(to: CGPoint(x: lx - 200, y: ly - 415))
    head.addQuadCurve(to: CGPoint(x: lx + 200, y: ly - 415), control: CGPoint(x: lx, y: ly - 640))
    head.closeSubpath()
    c.shape(head)
    c.stroke(line(lx, ly - 460, lx, ly + 460))
    c.shape(circle(lx - 220, ly - 160, 90))
    c.shape(circle(lx + 220, ly - 160, 90))
    c.shape(circle(lx - 180, ly + 220, 75))
    c.shape(circle(lx + 180, ly + 220, 75))
    c.stroke(line(lx - 100, ly - 540, lx - 180, ly - 700))
    c.stroke(line(lx + 100, ly - 540, lx + 180, ly - 700))
    c.shape(circle(lx - 195, ly - 725, 26))
    c.shape(circle(lx + 195, ly - 725, 26))
    c.stroke(wave(0, W, 1780, amp: 36, wavelength: 340))
}

sheets["packs/busybugs/BusyBugsSheet2"] = { c in
    // Butterfly with ringed wings
    let bx: CGFloat = 768, by: CGFloat = 950
    for (dx, dy, rx, ry) in [(-330.0, -300.0, 300.0, 270.0), (330.0, -300.0, 300.0, 270.0),
                             (-300.0, 280.0, 250.0, 220.0), (300.0, 280.0, 250.0, 220.0)] {
        c.shape(ellipse(bx + CGFloat(dx), by + CGFloat(dy), CGFloat(rx), CGFloat(ry)))
        c.shape(circle(bx + CGFloat(dx), by + CGFloat(dy), 90))
    }
    c.shape(ellipse(bx, by, 100, 400))
    c.stroke(line(bx - 35, by - 380, bx - 120, by - 560))
    c.stroke(line(bx + 35, by - 380, bx + 120, by - 560))
    c.shape(circle(bx - 140, by - 590, 30))
    c.shape(circle(bx + 140, by - 590, 30))
    flower(c, 360, 1650, 100, stemTo: 1950)
    flower(c, 1180, 1680, 90, stemTo: 1950)
}

sheets["packs/busybugs/BusyBugsSheet3"] = { c in
    // Snail
    c.shape(circle(880, 1050, 400))
    c.stroke(spiral(880, 1050, turns: 2.2, maxR: 360))
    let bodyPath = CGMutablePath()
    bodyPath.move(to: CGPoint(x: 500, y: 1450))
    bodyPath.addQuadCurve(to: CGPoint(x: 330, y: 1170), control: CGPoint(x: 310, y: 1440))
    bodyPath.addQuadCurve(to: CGPoint(x: 430, y: 1450), control: CGPoint(x: 430, y: 1300))
    bodyPath.addLine(to: CGPoint(x: 1350, y: 1450))
    bodyPath.addQuadCurve(to: CGPoint(x: 500, y: 1450), control: CGPoint(x: 920, y: 1620))
    bodyPath.closeSubpath()
    c.shape(bodyPath)
    c.stroke(line(345, 1180, 260, 1000))
    c.stroke(line(395, 1190, 420, 990))
    c.shape(circle(245, 975, 26))
    c.shape(circle(430, 962, 26))
    c.stroke(wave(0, W, 1650, amp: 34, wavelength: 320))
}

sheets["packs/busybugs/BusyBugsSheet4"] = { c in
    // Caterpillar
    let baseY: CGFloat = 1250
    var segX: CGFloat = 380
    for i in 0..<5 {
        let lift: CGFloat = i.isMultiple(of: 2) ? 0 : -70
        c.shape(circle(segX, baseY + lift, 150))
        segX += 210
    }
    c.shape(circle(380, baseY - 330, 190))                 // head
    c.shape(circle(320, baseY - 380, 26), fillColor: rgb(0, 0, 0))
    c.stroke(line(320, baseY - 500, 250, baseY - 660))
    c.stroke(line(440, baseY - 500, 510, baseY - 660))
    c.shape(circle(235, baseY - 685, 26))
    c.shape(circle(525, baseY - 685, 26))
    // Big leaf underfoot
    let leaf = CGMutablePath()
    leaf.move(to: CGPoint(x: 130, y: 1560))
    leaf.addQuadCurve(to: CGPoint(x: 1400, y: 1560), control: CGPoint(x: 768, y: 1290))
    leaf.addQuadCurve(to: CGPoint(x: 130, y: 1560), control: CGPoint(x: 768, y: 1860))
    leaf.closeSubpath()
    c.shape(leaf)
    c.stroke(line(180, 1560, 1360, 1560), width: 12)
}

// ---- Dino Days pack ----

sheets["packs/dinodays/DinoDaysSheet1"] = { c in
    // Long-neck dino
    c.shape(ellipse(820, 1300, 430, 260))                  // body
    let neck = CGMutablePath()
    neck.move(to: CGPoint(x: 520, y: 1240))
    neck.addQuadCurve(to: CGPoint(x: 390, y: 620), control: CGPoint(x: 330, y: 1000))
    neck.addLine(to: CGPoint(x: 560, y: 640))
    neck.addQuadCurve(to: CGPoint(x: 660, y: 1180), control: CGPoint(x: 540, y: 1000))
    c.shape(neck)
    c.shape(ellipse(470, 590, 150, 100))                   // head
    c.shape(circle(420, 570, 20), fillColor: rgb(0, 0, 0))
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: 1220, y: 1250))
    tail.addQuadCurve(to: CGPoint(x: 1470, y: 1050), control: CGPoint(x: 1430, y: 1260))
    tail.addQuadCurve(to: CGPoint(x: 1180, y: 1380), control: CGPoint(x: 1360, y: 1330))
    tail.closeSubpath()
    c.shape(tail)
    for lx: CGFloat in [620, 800, 980] {
        c.shape(rect(lx, 1480, 120, 260, corner: 50))
    }
    c.stroke(wave(0, W, 1780, amp: 34, wavelength: 340))
    c.shape(cloud(1150, 400, 420))
    sun(c, 250, 320, 110)
}

sheets["packs/dinodays/DinoDaysSheet2"] = { c in
    // Stegosaurus
    let body = CGMutablePath()
    body.move(to: CGPoint(x: 280, y: 1440))
    body.addQuadCurve(to: CGPoint(x: 760, y: 900), control: CGPoint(x: 360, y: 960))
    body.addQuadCurve(to: CGPoint(x: 1260, y: 1440), control: CGPoint(x: 1180, y: 960))
    body.closeSubpath()
    c.shape(body)
    // Head + tail
    c.shape(ellipse(240, 1320, 140, 90))
    c.shape(circle(190, 1295, 18), fillColor: rgb(0, 0, 0))
    c.shape(polygon([(1240, 1330), (1460, 1180), (1420, 1400)]))
    // Back plates
    for (px, py, s) in [(430.0, 1030.0, 100.0), (620.0, 900.0, 130.0),
                        (830.0, 890.0, 130.0), (1030.0, 1010.0, 100.0)] {
        let sz = CGFloat(s)
        c.shape(polygon([(CGFloat(px) - sz, CGFloat(py) + 40), (CGFloat(px), CGFloat(py) - sz),
                         (CGFloat(px) + sz, CGFloat(py) + 40)]))
    }
    for lx: CGFloat in [480, 960] {
        c.shape(rect(lx, 1420, 130, 280, corner: 55))
    }
    c.stroke(wave(0, W, 1760, amp: 34, wavelength: 340))
    c.shape(cloud(1200, 360, 400))
}

sheets["packs/dinodays/DinoDaysSheet3"] = { c in
    // Hatching egg
    let egg = CGMutablePath()
    egg.addEllipse(in: CGRect(x: 768 - 420, y: 700, width: 840, height: 1050))
    c.shape(egg)
    c.stroke(polygon([(400, 1150), (560, 1240), (700, 1120), (860, 1260), (1010, 1130), (1136, 1220)],
                     closed: false))
    // Baby dino head peeking over the crack
    c.shape(ellipse(700, 1000, 200, 150))
    c.shape(circle(640, 960, 22), fillColor: rgb(0, 0, 0))
    c.shape(circle(870, 1010, 40))
    // Grass tufts
    for gx: CGFloat in [250, 500, 1050, 1300] {
        c.stroke(line(gx, 1900, gx - 40, 1790))
        c.stroke(line(gx, 1900, gx, 1770))
        c.stroke(line(gx, 1900, gx + 40, 1790))
    }
    c.stroke(wave(0, W, 1900, amp: 30, wavelength: 340))
    c.shape(star(300, 400, outer: 80, inner: 36))
    c.shape(cloud(1150, 380, 420))
}

sheets["packs/dinodays/DinoDaysSheet4"] = { c in
    // Volcano
    c.shape(polygon([(300, 1700), (620, 650), (930, 650), (1250, 1700)]))
    let crater = CGMutablePath()
    crater.move(to: CGPoint(x: 620, y: 650))
    crater.addQuadCurve(to: CGPoint(x: 930, y: 650), control: CGPoint(x: 775, y: 740))
    c.stroke(crater)
    // Smoke puffs
    c.shape(cloud(700, 480, 330))
    c.shape(cloud(950, 330, 390))
    // Lava rivulets
    let lava = CGMutablePath()
    lava.move(to: CGPoint(x: 700, y: 660))
    lava.addQuadCurve(to: CGPoint(x: 640, y: 1050), control: CGPoint(x: 590, y: 850))
    c.stroke(lava)
    let lava2 = CGMutablePath()
    lava2.move(to: CGPoint(x: 850, y: 660))
    lava2.addQuadCurve(to: CGPoint(x: 940, y: 1000), control: CGPoint(x: 970, y: 820))
    c.stroke(lava2)
    c.stroke(wave(0, W, 1760, amp: 34, wavelength: 340))
    // Little dino watching
    c.shape(ellipse(340, 1600, 150, 90))
    c.shape(circle(230, 1520, 60))
    c.shape(circle(210, 1505, 14), fillColor: rgb(0, 0, 0))
}

// ---- Starry Night pack ----

sheets["packs/starrynight/StarryNightSheet1"] = { c in
    // Crescent moon
    let crescent = CGMutablePath()
    crescent.move(to: CGPoint(x: 830, y: 520))
    crescent.addQuadCurve(to: CGPoint(x: 830, y: 1480), control: CGPoint(x: 180, y: 1000))
    crescent.addQuadCurve(to: CGPoint(x: 830, y: 520), control: CGPoint(x: 560, y: 1000))
    crescent.closeSubpath()
    c.shape(crescent)
    c.shape(star(1150, 640, outer: 120, inner: 52))
    c.shape(star(1250, 1100, outer: 90, inner: 40))
    c.shape(star(1080, 1480, outer: 110, inner: 48))
    c.shape(star(330, 420, outer: 80, inner: 36))
    c.shape(cloud(500, 1780, 520))
}

sheets["packs/starrynight/StarryNightSheet2"] = { c in
    // Rocket
    let rx: CGFloat = 768
    c.shape(polygon([(rx - 170, 700), (rx, 380), (rx + 170, 700)]))     // nose
    c.shape(rect(rx - 170, 700, 340, 700, corner: 40))                   // body
    c.shape(circle(rx, 900, 110))                                        // window
    c.shape(circle(rx, 900, 70))
    c.shape(polygon([(rx - 170, 1180), (rx - 330, 1480), (rx - 170, 1400)])) // fins
    c.shape(polygon([(rx + 170, 1180), (rx + 330, 1480), (rx + 170, 1400)]))
    // Flame
    let flame = CGMutablePath()
    flame.move(to: CGPoint(x: rx - 110, y: 1400))
    flame.addQuadCurve(to: CGPoint(x: rx, y: 1780), control: CGPoint(x: rx - 140, y: 1650))
    flame.addQuadCurve(to: CGPoint(x: rx + 110, y: 1400), control: CGPoint(x: rx + 140, y: 1650))
    c.shape(flame)
    c.shape(star(320, 500, outer: 90, inner: 40))
    c.shape(star(1220, 420, outer: 70, inner: 32))
    c.shape(star(1250, 1650, outer: 100, inner: 44))
    c.shape(circle(300, 1750, 90))
}

sheets["packs/starrynight/StarryNightSheet3"] = { c in
    // Ringed planet
    c.shape(ellipse(768, 1020, 700, 190))
    c.shape(circle(768, 1020, 420))
    c.stroke(ellipse(768, 1020, 560, 140))
    // Craters
    c.shape(circle(600, 880, 70))
    c.shape(circle(900, 1150, 90))
    c.shape(circle(880, 830, 45))
    c.shape(star(280, 420, outer: 90, inner: 40))
    c.shape(star(1250, 500, outer: 110, inner: 48))
    c.shape(star(1200, 1680, outer: 80, inner: 36))
    c.shape(circle(340, 1700, 100))
}

sheets["packs/starrynight/StarryNightSheet4"] = { c in
    // Sleeping cloud with hanging stars
    let cl = cloud(768, 750, 900)
    c.shape(cl, lineWidth: 18)
    for dx: CGFloat in [-180, 60] {
        let eye = CGMutablePath()
        eye.move(to: CGPoint(x: 768 + dx, y: 760))
        eye.addQuadCurve(to: CGPoint(x: 768 + dx + 130, y: 760),
                         control: CGPoint(x: 768 + dx + 65, y: 850))
        c.stroke(eye)
    }
    for (sx, drop) in [(430.0, 380.0), (768.0, 560.0), (1100.0, 430.0)] {
        c.stroke(line(CGFloat(sx), 940, CGFloat(sx), 940 + CGFloat(drop)), width: 12)
        c.shape(star(CGFloat(sx), 1050 + CGFloat(drop), outer: 130, inner: 56))
    }
    c.shape(circle(280, 350, 90))
    c.shape(star(1280, 300, outer: 70, inner: 32))
}

// MARK: - Covers (1200×800, colorful)

var covers: [String: Draw] = [:]

covers["covers/ocean"] = { c in
    c.gradient(rgb(0.16, 0.55, 0.92), rgb(0.05, 0.28, 0.62))
    for (x, y, r) in [(180.0, 160.0, 34.0), (300.0, 90.0, 22.0), (1040.0, 180.0, 28.0)] {
        c.fill(circle(CGFloat(x), CGFloat(y), CGFloat(r)), color: rgb(1, 1, 1, 0.5))
    }
    c.fill(ellipse(560, 420, 260, 150), color: rgb(1, 0.78, 0.25))
    c.fill(polygon([(790, 420), (960, 310), (960, 530)]), color: rgb(1, 0.62, 0.15))
    c.fill(circle(430, 380, 22), color: rgb(0.1, 0.2, 0.4))
    c.stroke(wave(0, 1200, 660, amp: 26, wavelength: 220), width: 14, color: rgb(1, 1, 1, 0.75))
    c.stroke(wave(0, 1200, 730, amp: 22, wavelength: 190), width: 12, color: rgb(1, 1, 1, 0.45))
}

covers["covers/sunset"] = { c in
    c.gradient(rgb(1, 0.62, 0.24), rgb(0.94, 0.28, 0.44))
    c.fill(circle(600, 430, 210), color: rgb(1, 0.87, 0.35))
    for i in 0..<9 {
        let a = CGFloat(i) * .pi / 8 + .pi
        c.stroke(line(600 + cos(a) * 260, 430 + sin(a) * 260,
                      600 + cos(a) * 330, 430 + sin(a) * 330),
                 width: 16, color: rgb(1, 0.87, 0.35))
    }
    let hill = CGMutablePath()
    hill.move(to: CGPoint(x: 0, y: 620))
    hill.addQuadCurve(to: CGPoint(x: 1200, y: 640), control: CGPoint(x: 620, y: 500))
    hill.addLine(to: CGPoint(x: 1200, y: 800))
    hill.addLine(to: CGPoint(x: 0, y: 800))
    hill.closeSubpath()
    c.fill(hill, color: rgb(0.42, 0.16, 0.34))
}

covers["covers/forest"] = { c in
    c.gradient(rgb(0.55, 0.8, 0.45), rgb(0.16, 0.46, 0.26))
    for (tx, ty, s) in [(260.0, 430.0, 1.0), (620.0, 360.0, 1.35), (980.0, 450.0, 0.9)] {
        let sc = CGFloat(s)
        c.fill(rect(CGFloat(tx) - 26 * sc, CGFloat(ty) + 150 * sc, 52 * sc, 130 * sc),
               color: rgb(0.45, 0.3, 0.18))
        for tier in 0..<3 {
            let t = CGFloat(tier)
            c.fill(polygon([(CGFloat(tx) - (150 - t * 34) * sc, CGFloat(ty) + (160 - t * 100) * sc),
                            (CGFloat(tx), CGFloat(ty) + (-90 - t * 100) * sc),
                            (CGFloat(tx) + (150 - t * 34) * sc, CGFloat(ty) + (160 - t * 100) * sc)]),
                   color: rgb(0.09, 0.35, 0.2))
        }
    }
    for (x, y) in [(150.0, 690.0), (420.0, 720.0), (800.0, 700.0), (1080.0, 730.0)] {
        c.fill(circle(CGFloat(x), CGFloat(y), 12), color: rgb(1, 1, 1, 0.6))
    }
}

covers["covers/firstshapes"] = { c in
    c.gradient(rgb(1, 0.78, 0.25), rgb(0.96, 0.6, 0.12))
    c.fill(circle(300, 300, 150), color: rgb(1, 1, 1, 0.9))
    c.fill(polygon([(760, 440), (900, 180), (1040, 440)]), color: rgb(1, 1, 1, 0.75))
    c.fill(rect(480, 480, 240, 240, corner: 30), color: rgb(1, 1, 1, 0.6))
    c.fill(star(1000, 620, outer: 130, inner: 56), color: rgb(1, 1, 1, 0.85))
    c.fill(heart(220, 620, width: 220), color: rgb(1, 1, 1, 0.7))
}

covers["covers/busybugs"] = { c in
    c.gradient(rgb(0.62, 0.85, 0.44), rgb(0.3, 0.62, 0.3))
    // Ladybug
    c.fill(circle(380, 420, 190), color: rgb(0.92, 0.26, 0.21))
    c.fill(circle(380, 205, 80), color: rgb(0.15, 0.12, 0.12))
    c.stroke(line(380, 240, 380, 610), width: 14, color: rgb(0.15, 0.12, 0.12))
    for (dx, dy) in [(-90.0, -60.0), (90.0, -60.0), (-70.0, 90.0), (70.0, 90.0)] {
        c.fill(circle(380 + CGFloat(dx), 420 + CGFloat(dy), 34), color: rgb(0.15, 0.12, 0.12))
    }
    // Bee
    c.fill(ellipse(870, 480, 170, 115), color: rgb(1, 0.8, 0.2))
    for dx: CGFloat in [-60, 10, 80] {
        c.fill(rect(870 + dx - 16, 375, 32, 210, corner: 16), color: rgb(0.15, 0.12, 0.12))
    }
    c.fill(ellipse(800, 310, 95, 55), color: rgb(1, 1, 1, 0.85))
    c.fill(ellipse(960, 310, 95, 55), color: rgb(1, 1, 1, 0.85))
    // Flower
    for i in 0..<6 {
        let a = CGFloat(i) * .pi / 3
        c.fill(circle(640 + cos(a) * 52, 690 + sin(a) * 52, 34), color: rgb(1, 1, 1, 0.9))
    }
    c.fill(circle(640, 690, 30), color: rgb(1, 0.8, 0.2))
}

covers["covers/dinodays"] = { c in
    c.gradient(rgb(0.35, 0.75, 0.68), rgb(0.13, 0.45, 0.42))
    // Volcano
    c.fill(polygon([(820, 620), (960, 260), (1100, 620)]), color: rgb(0.42, 0.3, 0.28))
    c.fill(circle(960, 230, 55), color: rgb(0.95, 0.95, 0.95, 0.85))
    c.fill(circle(1040, 180, 40), color: rgb(0.95, 0.95, 0.95, 0.7))
    // Dino
    c.fill(ellipse(430, 500, 220, 130), color: rgb(0.32, 0.62, 0.28))
    let neck = polygon([(280, 470), (230, 220), (330, 240), (360, 460)])
    c.fill(neck, color: rgb(0.32, 0.62, 0.28))
    c.fill(ellipse(270, 210, 75, 50), color: rgb(0.32, 0.62, 0.28))
    c.fill(polygon([(630, 480), (790, 380), (760, 520)]), color: rgb(0.32, 0.62, 0.28))
    for lx: CGFloat in [340, 480] {
        c.fill(rect(lx, 590, 60, 120, corner: 26), color: rgb(0.32, 0.62, 0.28))
    }
    c.fill(circle(245, 195, 10), color: rgb(0.1, 0.15, 0.1))
}

covers["covers/starrynight"] = { c in
    c.gradient(rgb(0.2, 0.2, 0.5), rgb(0.08, 0.07, 0.24))
    // Crescent
    c.fill(circle(340, 300, 150), color: rgb(1, 0.87, 0.35))
    c.fill(circle(410, 250, 130), color: rgb(0.16, 0.15, 0.4))
    for (x, y, s) in [(700.0, 180.0, 40.0), (950.0, 320.0, 55.0), (820.0, 560.0, 34.0),
                      (180.0, 600.0, 44.0), (1080.0, 620.0, 30.0)] {
        c.fill(star(CGFloat(x), CGFloat(y), outer: CGFloat(s), inner: CGFloat(s) * 0.44),
               color: rgb(1, 0.95, 0.7))
    }
    // Tiny rocket
    c.fill(rect(560, 380, 90, 180, corner: 24), color: rgb(0.92, 0.93, 0.97))
    c.fill(polygon([(560, 380), (605, 300), (650, 380)]), color: rgb(0.92, 0.3, 0.3))
    c.fill(circle(605, 450, 26), color: rgb(0.3, 0.5, 0.9))
    c.fill(polygon([(560, 520), (520, 590), (560, 570)]), color: rgb(0.92, 0.3, 0.3))
    c.fill(polygon([(650, 520), (690, 590), (650, 570)]), color: rgb(0.92, 0.3, 0.3))
    c.fill(polygon([(575, 565), (605, 660), (635, 565)]), color: rgb(1, 0.7, 0.2))
}

// MARK: - Render everything

let artRoot = URL(fileURLWithPath: "art")

for (name, draw) in sheets.sorted(by: { $0.key < $1.key }) {
    let canvas = Canvas(width: Int(W), height: Int(H))
    draw(canvas)
    canvas.save(to: artRoot.appendingPathComponent("\(name).png"))
    print("sheet  \(name)")
}

for (name, draw) in covers.sorted(by: { $0.key < $1.key }) {
    let canvas = Canvas(width: 1200, height: 800)
    draw(canvas)
    canvas.save(to: artRoot.appendingPathComponent("\(name).png"))
    print("cover  \(name)")
}

print("done: \(sheets.count) sheets + \(covers.count) covers -> art/")
