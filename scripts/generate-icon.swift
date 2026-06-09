#!/usr/bin/env swift
//
// generate-icon.swift
// Generates the SuperPaste app icon at all required macOS asset catalog sizes
// and writes the .icns file used by the packaged app.
//
// Design: dark macOS squircle (with standard transparent margins) containing
// a keycap with a glowing blue ⌥V — the brand mark used across the website.
//
// Usage: swift scripts/generate-icon.swift
//

import AppKit

let outputDir = "SuperPaste/Resources/Assets.xcassets/AppIcon.appiconset"
let icnsOutputPath = "SuperPaste/Resources/AppIcon.icns"

let iconSizes: [(name: String, pixels: Int)] = [
    ("icon_16x16",      16),
    ("icon_16x16@2x",   32),
    ("icon_32x32",      32),
    ("icon_32x32@2x",   64),
    ("icon_128x128",    128),
    ("icon_128x128@2x", 256),
    ("icon_256x256",    256),
    ("icon_256x256@2x", 512),
    ("icon_512x512",    512),
    ("icon_512x512@2x", 1024),
]

let brandBlue = CGColor(red: 0.10, green: 0.50, blue: 0.95, alpha: 1.0)

// MARK: - Icon Generator

func generateIcon(pixelSize: Int) -> Data? {
    let s = CGFloat(pixelSize)

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    guard let gfx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gfx
    let ctx = gfx.cgContext
    let cs = CGColorSpaceCreateDeviceRGB()

    // 1. Squircle tile on the standard macOS icon grid (~80.5% of canvas,
    //    transparent margin all around).
    let tileSize = s * 0.805
    let tile = CGRect(
        x: (s - tileSize) / 2,
        y: (s - tileSize) / 2,
        width: tileSize,
        height: tileSize
    )
    let tilePath = CGPath(
        roundedRect: tile,
        cornerWidth: tileSize * 0.225,
        cornerHeight: tileSize * 0.225,
        transform: nil
    )

    // Drop shadow behind the tile (subtle, like system icons)
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.008),
        blur: s * 0.02,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.30)
    )
    ctx.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1.0))
    ctx.addPath(tilePath)
    ctx.fillPath()
    ctx.restoreGState()

    // Everything else clips to the tile
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()

    // 2. Near-black vertical gradient
    let bgColors = [
        CGColor(red: 0.15, green: 0.15, blue: 0.17, alpha: 1.0),
        CGColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1.0),
    ] as CFArray
    if let bg = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            bg,
            start: CGPoint(x: s / 2, y: s),
            end:   CGPoint(x: s / 2, y: 0),
            options: []
        )
    }

    // 3. Soft blue ambience behind the keycap
    let ambience = [
        CGColor(red: 0.10, green: 0.50, blue: 0.95, alpha: 0.28),
        CGColor(red: 0.10, green: 0.50, blue: 0.95, alpha: 0.0),
    ] as CFArray
    if let glow = CGGradient(colorsSpace: cs, colors: ambience, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: s * 0.5, y: s * 0.52),
            startRadius: 0,
            endCenter:   CGPoint(x: s * 0.5, y: s * 0.52),
            endRadius:   s * 0.45,
            options: []
        )
    }

    // 4. Keycap + glyph (keycap only at sizes where it can render cleanly)
    if pixelSize >= 48 {
        drawKeycap(ctx: ctx, size: s, colorSpace: cs)
        drawGlyph(size: s, fontSize: s * 0.235, center: CGPoint(x: s * 0.5, y: s * 0.515))
    } else {
        // Tiny sizes: just the glyph, as large as legibility allows
        drawGlyph(size: s, fontSize: s * 0.42, center: CGPoint(x: s * 0.5, y: s * 0.5))
    }

    // 5. Hairline inner border on the tile
    ctx.addPath(tilePath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.07))
    ctx.setLineWidth(max(1.0, s * 0.006))
    ctx.strokePath()

    ctx.restoreGState() // tile clip

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// MARK: - Keycap

func drawKeycap(ctx: CGContext, size s: CGFloat, colorSpace cs: CGColorSpace) {
    let capW = s * 0.50
    let capH = s * 0.38
    let capX = (s - capW) / 2
    let capY = (s - capH) / 2 + s * 0.01
    let corner = s * 0.075
    let depth = s * 0.022

    // Keycap base (the darker "side" visible below the top face)
    let base = CGRect(x: capX, y: capY - depth, width: capW, height: capH)
    ctx.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0))
    ctx.addPath(CGPath(roundedRect: base, cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.fillPath()

    // Keycap top face
    let face = CGRect(x: capX, y: capY, width: capW, height: capH)
    let facePath = CGPath(roundedRect: face, cornerWidth: corner, cornerHeight: corner, transform: nil)

    ctx.saveGState()
    ctx.addPath(facePath)
    ctx.clip()
    let faceColors = [
        CGColor(red: 0.20, green: 0.20, blue: 0.23, alpha: 1.0),
        CGColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1.0),
    ] as CFArray
    if let g = CGGradient(colorsSpace: cs, colors: faceColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            g,
            start: CGPoint(x: s / 2, y: face.maxY),
            end:   CGPoint(x: s / 2, y: face.minY),
            options: []
        )
    }
    ctx.restoreGState()

    // Keycap border
    ctx.addPath(facePath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
    ctx.setLineWidth(max(1.0, s * 0.007))
    ctx.strokePath()
}

// MARK: - Glyph

func drawGlyph(size s: CGFloat, fontSize: CGFloat, center: CGPoint) {
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(cgColor: brandBlue) ?? .systemBlue,
        .kern: fontSize * 0.06,
    ]
    let text = NSAttributedString(string: "⌥V", attributes: attrs)
    let textSize = text.size()

    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.saveGState()
    ctx.setShadow(
        offset: .zero,
        blur: fontSize * 0.45,
        color: CGColor(red: 0.10, green: 0.50, blue: 0.95, alpha: 0.85)
    )
    // Vertically center on the glyph's visual bounds (cap height), not the
    // full line box, so the mark doesn't sit low in the keycap.
    let visualMidOffset = font.capHeight / 2 + font.descender
    let origin = CGPoint(
        x: center.x - textSize.width / 2,
        y: center.y - textSize.height / 2 - visualMidOffset / 2
    )
    text.draw(at: origin)
    ctx.restoreGState()
}

// MARK: - Generate All Sizes

for icon in iconSizes {
    guard let data = generateIcon(pixelSize: icon.pixels) else {
        print("FAIL  \(icon.name)")
        continue
    }
    let path = "\(outputDir)/\(icon.name).png"
    try! data.write(to: URL(fileURLWithPath: path))
    print("  OK  \(icon.name).png  (\(icon.pixels)px)")
}

print("\nAll icons generated in \(outputDir)/")

try! writeICNS()
print("  OK  AppIcon.icns")

// MARK: - ICNS Writer

func writeICNS() throws {
    let resources: [(type: String, filename: String)] = [
        ("ic11", "icon_16x16@2x.png"),
        ("ic12", "icon_32x32@2x.png"),
        ("ic07", "icon_128x128.png"),
        ("ic13", "icon_128x128@2x.png"),
        ("ic08", "icon_256x256.png"),
        ("ic14", "icon_256x256@2x.png"),
        ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png"),
    ]

    var chunks = Data()
    for resource in resources {
        let pngPath = "\(outputDir)/\(resource.filename)"
        let pngData = try Data(contentsOf: URL(fileURLWithPath: pngPath))
        appendFourCC(resource.type, to: &chunks)
        appendUInt32BE(UInt32(pngData.count + 8), to: &chunks)
        chunks.append(pngData)
    }

    var icns = Data()
    appendFourCC("icns", to: &icns)
    appendUInt32BE(UInt32(chunks.count + 8), to: &icns)
    icns.append(chunks)
    try icns.write(to: URL(fileURLWithPath: icnsOutputPath))
}

func appendFourCC(_ value: String, to data: inout Data) {
    data.append(value.data(using: .ascii)!)
}

func appendUInt32BE(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { bytes in
        data.append(contentsOf: bytes)
    }
}
