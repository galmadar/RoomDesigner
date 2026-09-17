// Draws the Roomsmith app icon and writes the asset catalog.
// Pure CoreGraphics so it needs no toolchain beyond a Swift compiler.
//
//   swiftc -O -o icon Tools/AppIcon/main.swift
//   ./icon icons Assets.xcassets/AppIcon.appiconset    # the shipped PNGs
//   ./icon sheet <dir>                                 # before/after review sheet
//
// Direction "Plan": an overhead floor plan — heavy ink walls, oak floor, one
// darker block, the window as the single accent segment. It was chosen over a
// perspective corner because it is the only one with a silhouette and the only
// one still legible at 40 px, which is where an icon actually lives.
//
// No alpha anywhere: every context is noneSkipLast, so the PNGs are colour
// type 2 and Apple's "no transparency" rule is satisfied by construction.

import Foundation
import CoreGraphics
import CoreText
import ImageIO

// MARK: - Colour

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func comps(_ c: CGColor) -> [CGFloat] { c.components ?? [0, 0, 0, 1] }

func shade(_ c: CGColor, _ f: CGFloat) -> CGColor {
    let x = comps(c)
    return CGColor(red: min(x[0] * f, 1), green: min(x[1] * f, 1), blue: min(x[2] * f, 1), alpha: 1)
}

/// WCAG relative luminance, used to check that warming the ground did not
/// quietly collapse the plan into one beige mass.
func luminance(_ hex: UInt32) -> CGFloat {
    func ch(_ v: CGFloat) -> CGFloat {
        v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    let r = ch(CGFloat((hex >> 16) & 0xFF) / 255)
    let g = ch(CGFloat((hex >> 8) & 0xFF) / 255)
    let b = ch(CGFloat(hex & 0xFF) / 255)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

func contrast(_ a: UInt32, _ b: UInt32) -> CGFloat {
    let x = luminance(a), y = luminance(b)
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}

// MARK: - Style

struct Style {
    var ground: UInt32
    var groundDeep: UInt32?     // nil draws a flat ground
    var ink: UInt32
    var floor: UInt32 = 0xB78C5C        // Palette.swift warm oak
    var accent: UInt32 = 0xB8763C       // Paper.fallbackAccent
    var blockFactor: CGFloat = 0.72
}

/// The icon as originally chosen. Kept so the review sheet can show the cost.
let cold = Style(ground: 0xFAF8F5, groundDeep: nil, ink: 0x1C1917)

/// Shipped. The ground is warm linen on a slight diagonal gradient rather than
/// near-white, so the tile stops reading as a glaring white slab on a dark home
/// screen; the ink is warmed off neutral black to match. Floor and accent are
/// untouched — they are what makes the plan readable and were not the problem.
let warm = Style(ground: 0xF0E5D3, groundDeep: 0xE2D2B6, ink: 0x231C15)

// MARK: - Drawing

typealias Pt = (CGFloat, CGFloat)

func poly(_ c: CGContext, _ pts: [Pt], _ fill: CGColor) {
    c.beginPath()
    c.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
    for p in pts.dropFirst() { c.addLine(to: CGPoint(x: p.0, y: p.1)) }
    c.closePath()
    c.setFillColor(fill)
    c.fillPath()
}

func line(_ c: CGContext, _ a: Pt, _ b: Pt, _ color: CGColor, _ w: CGFloat) {
    c.setStrokeColor(color)
    c.setLineWidth(w)
    c.setLineCap(.butt)
    c.beginPath()
    c.move(to: CGPoint(x: a.0, y: a.1))
    c.addLine(to: CGPoint(x: b.0, y: b.1))
    c.strokePath()
}

/// The room outline. An alcove rather than a plain rectangle, nudged so the bite
/// out of the bottom-right makes the mass lean the other way. Nothing sits in the
/// corners, which iOS clips under its own mask.
let plan: [Pt] = [(0.185, 0.185), (0.865, 0.185), (0.865, 0.570),
                  (0.655, 0.570), (0.655, 0.855), (0.185, 0.855)]

func drawPlan(_ c: CGContext, px: CGFloat, _ s: Style) {
    if let deep = s.groundDeep {
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [rgb(s.ground), rgb(deep)] as CFArray,
                              locations: [0, 1])!
        c.saveGState()
        c.clip(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 1, y: 1),
                             options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        c.restoreGState()
    } else {
        poly(c, [(0, 0), (1, 0), (1, 1), (0, 1)], rgb(s.ground))
    }

    poly(c, plan, rgb(s.floor))

    // One thing standing in it, so the floor is a room and not a swatch.
    poly(c, [(0.245, 0.290), (0.395, 0.290), (0.395, 0.575), (0.245, 0.575)],
         shade(rgb(s.floor), s.blockFactor))

    // Walls never thinner than ~2.2 device pixels: the silhouette is the whole
    // point, so it gets a floor rather than dissolving at Spotlight size.
    let wall = max(0.055, 2.2 / px)
    c.setLineJoin(.miter)
    c.setLineCap(.butt)
    c.setStrokeColor(rgb(s.ink))
    c.setLineWidth(wall)
    c.beginPath()
    c.move(to: CGPoint(x: plan[0].0, y: plan[0].1))
    for p in plan.dropFirst() { c.addLine(to: CGPoint(x: p.0, y: p.1)) }
    c.closePath()
    c.strokePath()

    // The window — the one accent, and the thing the app promises to keep.
    // No door: a gap in the bottom wall left the shape standing on two feet.
    line(c, (0.370, 0.185), (0.650, 0.185), rgb(s.accent), wall)
}

// MARK: - Render plumbing

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    // noneSkipLast: opaque RGB, so the PNG carries no alpha channel at all.
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    c.setShouldAntialias(true)
    c.interpolationQuality = .high
    return c
}

func renderIcon(_ s: Style, px: Int) -> CGImage {
    let ss = 4                                      // supersample, then box down
    let side = px * ss
    let c = makeContext(side, side)
    c.translateBy(x: 0, y: CGFloat(side))
    c.scaleBy(x: 1, y: -1)                          // top-left origin
    c.scaleBy(x: CGFloat(side), y: CGFloat(side))   // unit square
    drawPlan(c, px: CGFloat(px), s)
    let big = c.makeImage()!
    let d = makeContext(px, px)
    d.draw(big, in: CGRect(x: 0, y: 0, width: px, height: px))
    return d.makeImage()!
}

func writePNG(_ img: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(path)") }
}

// MARK: - Asset catalog

/// Every size iOS asks an iPhone-only app for: notification, settings,
/// Spotlight and home screen at 2x and 3x, plus the App Store artwork.
let entries: [(size: String, scale: String, idiom: String, px: Int)] = [
    ("20x20", "2x", "iphone", 40),
    ("20x20", "3x", "iphone", 60),
    ("29x29", "2x", "iphone", 58),
    ("29x29", "3x", "iphone", 87),
    ("40x40", "2x", "iphone", 80),
    ("40x40", "3x", "iphone", 120),
    ("60x60", "2x", "iphone", 120),
    ("60x60", "3x", "iphone", 180),
    ("1024x1024", "1x", "ios-marketing", 1024),
]

func makeIcons(_ dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

    for px in Set(entries.map(\.px)).sorted() {
        writePNG(renderIcon(warm, px: px), "\(dir)/AppIcon-\(px).png")
        print("  AppIcon-\(px).png")
    }

    let images = entries.map { e in
        """
            {
              "filename" : "AppIcon-\(e.px).png",
              "idiom" : "\(e.idiom)",
              "scale" : "\(e.scale)",
              "size" : "\(e.size)"
            }
        """
    }.joined(separator: ",\n")

    let json = """
    {
      "images" : [
    \(images)
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """
    try! json.write(toFile: "\(dir)/Contents.json", atomically: true, encoding: .utf8)
    print("  Contents.json — \(entries.count) entries")
}

// MARK: - Review sheet

func place(_ c: CGContext, _ img: CGImage, _ r: CGRect, smooth: Bool = true) {
    c.saveGState()
    c.interpolationQuality = smooth ? .high : .none
    c.translateBy(x: r.minX, y: r.maxY)
    c.scaleBy(x: 1, y: -1)
    c.draw(img, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
    c.restoreGState()
}

func roundedPath(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}

enum Align { case left, center }

func text(_ c: CGContext, _ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat,
          color: CGColor, font: String = "HelveticaNeue", align: Align = .left) {
    let f = CTFontCreateWithName(font as CFString, size, nil)
    let attr = NSAttributedString(string: s, attributes: [
        kCTFontAttributeName as NSAttributedString.Key: f,
        kCTForegroundColorAttributeName as NSAttributedString.Key: color,
    ])
    let ctLine = CTLineCreateWithAttributedString(attr)
    let width = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
    c.saveGState()
    c.translateBy(x: x + (align == .center ? -width / 2 : 0), y: y)
    c.scaleBy(x: 1, y: -1)
    c.textPosition = .zero
    CTLineDraw(ctLine, c)
    c.restoreGState()
}

/// iOS applies this corner mask itself; the files must stay square.
let maskRatio: CGFloat = 0.2237

func homeScreen(_ ctx: CGContext, _ r: CGRect, dark: Bool) {
    ctx.saveGState()
    ctx.addPath(roundedPath(r, 30))
    ctx.clip()

    let space = CGColorSpaceCreateDeviceRGB()
    // Wallpaper of our own — nothing borrowed.
    let colors: [CGColor] = dark
        ? [rgb(0x3A2E23), rgb(0x1A1511), rgb(0x0E0C0A)]
        : [rgb(0xF6F0E6), rgb(0xE8DCCB), rgb(0xD8C7B0)]
    let grad = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: r.minX, y: r.minY),
                           end: CGPoint(x: r.minX + r.width * 0.5, y: r.maxY),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    let glow = CGGradient(colorsSpace: space,
                          colors: [rgb(0xB8763C, dark ? 0.30 : 0.22), rgb(0xB8763C, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: r.minX + r.width * 0.75, y: r.minY + 50),
                           startRadius: 0,
                           endCenter: CGPoint(x: r.minX + r.width * 0.75, y: r.minY + 50),
                           endRadius: r.width * 0.6, options: [])

    let label = dark ? rgb(0xFFFFFF) : rgb(0x2A231C)
    text(ctx, dark ? "Dark home screen" : "Light home screen", r.minX + 24, r.minY + 34,
         size: 20, color: label, font: "HelveticaNeue-Medium")

    let icon: CGFloat = 132, gap: CGFloat = 52
    let gridW = icon * 3 + gap * 2
    let gx = r.minX + (r.width - gridW) / 2
    let gy = r.minY + 76

    func cell(_ col: Int, _ row: Int) -> CGRect {
        CGRect(x: gx + CGFloat(col) * (icon + gap), y: gy + CGFloat(row) * (icon + 74),
               width: icon, height: icon)
    }

    for (i, pair) in [(cold, "before"), (warm, "after")].enumerated() {
        let rr = cell(i, 0)
        ctx.saveGState()
        ctx.addPath(roundedPath(rr, icon * maskRatio))
        ctx.clip()
        place(ctx, renderIcon(pair.0, px: 180), rr)
        ctx.restoreGState()
        text(ctx, "Roomsmith", rr.midX, rr.maxY + 24, size: 17, color: label, align: .center)
        text(ctx, pair.1, rr.midX, rr.maxY + 46, size: 15,
             color: dark ? rgb(0xD9924F) : rgb(0x9A6A38), align: .center)
    }

    // Neighbours, so the tile is judged next to something rather than alone.
    let fillers: [(UInt32, String)] = [(0x4C6B7A, "Notes"), (0x6E7F5B, "Weather"),
                                       (0x8A6A78, "Reading"), (0x5B5F6B, "Files")]
    var n = 2
    for f in fillers {
        let rr = cell(n % 3, n / 3)
        ctx.saveGState()
        ctx.addPath(roundedPath(rr, icon * maskRatio))
        ctx.clip()
        ctx.setFillColor(rgb(f.0))
        ctx.fill(rr)
        ctx.setFillColor(rgb(0xFFFFFF, 0.13))
        ctx.fill(CGRect(x: rr.minX, y: rr.midY, width: rr.width, height: rr.height / 2))
        ctx.setFillColor(rgb(0xFFFFFF, 0.5))
        ctx.fill(CGRect(x: rr.midX - 26, y: rr.midY - 26, width: 52, height: 52))
        ctx.restoreGState()
        text(ctx, f.1, rr.midX, rr.maxY + 24, size: 17,
             color: dark ? rgb(0xFFFFFF, 0.85) : rgb(0x2A231C, 0.8), align: .center)
        n += 1
    }
    ctx.restoreGState()
}

func makeSheet(_ dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

    let W = 1600, H = 1900
    let m: CGFloat = 60
    let ctx = makeContext(W, H)
    ctx.translateBy(x: 0, y: CGFloat(H))
    ctx.scaleBy(x: 1, y: -1)
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(W), height: CGFloat(H)))

    let ink = rgb(0x1C1917), quiet = rgb(0x79706A)
    text(ctx, "Roomsmith app icon — warming direction C", m, 64, size: 36,
         color: ink, font: "HelveticaNeue-Medium")
    text(ctx, "Geometry is byte-identical between the two. Only the ground and the ink changed.",
         m, 100, size: 19, color: quiet)
    text(ctx, "Near-white FAF8F5 becomes a warm linen gradient F0E5D3 to E2D2B6; ink 1C1917 becomes 231C15.",
         m, 126, size: 19, color: quiet)

    // Big pair.
    var y: CGFloat = 150
    let big: CGFloat = 380
    for (i, pair) in [(cold, "Before — as chosen"), (warm, "After — warmed")].enumerated() {
        let x = m + CGFloat(i) * (big + 90)
        let r = CGRect(x: x, y: y, width: big, height: big)
        place(ctx, renderIcon(pair.0, px: 1024), r)
        ctx.setStrokeColor(rgb(0xDDD4C8)); ctx.setLineWidth(1); ctx.stroke(r)
        text(ctx, pair.1, x, y + big + 32, size: 23, color: ink, font: "HelveticaNeue-Medium")
    }

    // Numbers, so "it still works small" is a measurement and not a claim.
    let cx = m + (big + 90) * 2
    text(ctx, "Contrast ratios", cx, y + 26, size: 22, color: ink, font: "HelveticaNeue-Medium")
    // Mid-gradient, which is what most of the warmed tile actually is.
    let midWarm: UInt32 = 0xE9DBC4
    let rows = [
        ("wall vs ground", contrast(cold.ink, cold.ground), contrast(warm.ink, midWarm)),
        ("floor vs ground", contrast(cold.floor, cold.ground), contrast(warm.floor, midWarm)),
        ("wall vs floor", contrast(cold.ink, cold.floor), contrast(warm.ink, warm.floor)),
    ]
    var ry = y + 62
    text(ctx, "before      after", cx + 210, ry, size: 17, color: quiet)
    ry += 28
    for (name, b, a) in rows {
        text(ctx, name, cx, ry, size: 18, color: quiet)
        text(ctx, String(format: "%.2f", b), cx + 212, ry, size: 18, color: ink)
        text(ctx, String(format: "%.2f", a), cx + 282, ry, size: 18, color: ink)
        ry += 30
    }
    text(ctx, "The silhouette is carried by wall-vs-ground,", cx, ry + 24, size: 17, color: quiet)
    text(ctx, "which stays far above anything that could", cx, ry + 48, size: 17, color: quiet)
    text(ctx, "blur. Warming costs a little floor separation.", cx, ry + 72, size: 17, color: quiet)

    y += big + 96

    // True sizes.
    text(ctx, "At true pixel size — 180, 120, 87, 80, 60, 58, 40 — and 40 px magnified x6, unsmoothed",
         m, y + 26, size: 21, color: ink, font: "HelveticaNeue-Medium")
    y += 50

    let sizes = [180, 120, 87, 80, 60, 58, 40]
    for (i, pair) in [(cold, "before"), (warm, "after")].enumerated() {
        let rowY = y + CGFloat(i) * 260
        text(ctx, pair.1, m, rowY + 130, size: 19, color: quiet, font: "HelveticaNeue-Medium")
        var x = m + 110
        for s in sizes {
            let r = CGRect(x: x, y: rowY + (250 - CGFloat(s)) / 2, width: CGFloat(s), height: CGFloat(s))
            place(ctx, renderIcon(pair.0, px: s), r)
            ctx.setStrokeColor(rgb(0xDDD4C8)); ctx.setLineWidth(1); ctx.stroke(r)
            x += CGFloat(s) + 22
        }
        let mag = CGRect(x: x + 40, y: rowY + 5, width: 240, height: 240)
        place(ctx, renderIcon(pair.0, px: 40), mag, smooth: false)
        ctx.setStrokeColor(rgb(0xDDD4C8)); ctx.setLineWidth(1); ctx.stroke(mag)

        // The same 40 px under the mask iOS actually applies.
        let masked = CGRect(x: x + 310, y: rowY + 55, width: 140, height: 140)
        ctx.setFillColor(i == 0 ? rgb(0x14110E) : rgb(0x14110E))
        ctx.fill(CGRect(x: x + 290, y: rowY + 5, width: 180, height: 240))
        ctx.saveGState()
        ctx.addPath(roundedPath(masked, 140 * maskRatio))
        ctx.clip()
        place(ctx, renderIcon(pair.0, px: 140), masked)
        ctx.restoreGState()
    }
    y += 520 + 30

    // Home screens.
    let panelW = (CGFloat(W) - m * 2 - 40) / 2
    let panelH = CGFloat(H) - y - m
    homeScreen(ctx, CGRect(x: m, y: y, width: panelW, height: panelH), dark: true)
    homeScreen(ctx, CGRect(x: m + panelW + 40, y: y, width: panelW, height: panelH), dark: false)

    writePNG(ctx.makeImage()!, "\(dir)/warming-comparison.png")
    print("  warming-comparison.png")

    // The two home screens on their own, full size.
    for dark in [true, false] {
        let pw = 900, ph = 640
        let c = makeContext(pw, ph)
        c.translateBy(x: 0, y: CGFloat(ph))
        c.scaleBy(x: 1, y: -1)
        c.setFillColor(rgb(0xFFFFFF))
        c.fill(CGRect(x: 0, y: 0, width: CGFloat(pw), height: CGFloat(ph)))
        homeScreen(c, CGRect(x: 0, y: 0, width: CGFloat(pw), height: CGFloat(ph)), dark: dark)
        let name = dark ? "home-dark.png" : "home-light.png"
        writePNG(c.makeImage()!, "\(dir)/\(name)")
        print("  \(name)")
    }

    // Before and after at 1024, on their own, for a close look.
    writePNG(renderIcon(cold, px: 1024), "\(dir)/before-1024.png")
    writePNG(renderIcon(warm, px: 1024), "\(dir)/after-1024.png")
    print("  before-1024.png, after-1024.png")
}

// MARK: - Main

let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "icons"
let dir = args.count > 2 ? args[2] : "Assets.xcassets/AppIcon.appiconset"

switch mode {
case "icons":
    print("writing icons to \(dir)")
    makeIcons(dir)
case "sheet":
    print("writing sheet to \(dir)")
    makeSheet(dir)
case "contrast":
    // Mid-gradient ground, which is what most of the tile actually is.
    let midWarm: UInt32 = 0xE9DBC4
    print(String(format: "wall vs ground   before %.2f   after %.2f",
                 contrast(cold.ink, cold.ground), contrast(warm.ink, midWarm)))
    print(String(format: "floor vs ground  before %.2f   after %.2f",
                 contrast(cold.floor, cold.ground), contrast(warm.floor, midWarm)))
    print(String(format: "wall vs floor    before %.2f   after %.2f",
                 contrast(cold.ink, cold.floor), contrast(warm.ink, warm.floor)))
default:
    print("usage: icon [icons|sheet|contrast] <dir>")
    exit(1)
}
