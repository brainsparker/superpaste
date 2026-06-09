#!/usr/bin/env swift
//
// generate-icon.swift
// Generates the SuperPaste app icon at all required macOS asset catalog sizes
// and writes the .icns file used by the packaged app.
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

    // 1. Background gradient
    let cs = CGColorSpaceCreateDeviceRGB()

    let bgColors = [
        CGColor(red: 0.02, green: 0.25, blue: 0.47, alpha: 1.0),
        CGColor(red: 0.00, green: 0.53, blue: 0.72, alpha: 1.0),
        CGColor(red: 0.18, green: 0.78, blue: 0.65, alpha: 1.0),
    ] as CFArray

    if let bg = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0.0, 0.50, 1.0]) {
        ctx.drawLinearGradient(
            bg,
            start: CGPoint(x: 0, y: 0),                // bottom-left
            end:   CGPoint(x: s, y: s),                 // top-right
            options: [.drawsAfterEndLocation, .drawsBeforeStartLocation]
        )
    }

    // 2. Soft depth glows
    let glowColors = [
        CGColor(red: 0.88, green: 1.00, blue: 0.94, alpha: 0.22),
        CGColor(red: 0.88, green: 1.00, blue: 0.94, alpha: 0.0),
    ] as CFArray
    if let glow = CGGradient(colorsSpace: cs, colors: glowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: s * 0.58, y: s * 0.60),
            startRadius: 0,
            endCenter:   CGPoint(x: s * 0.58, y: s * 0.60),
            endRadius:   s * 0.58,
            options: []
        )
    }

    // 3. Paste mark
    drawPasteMark(ctx: ctx, size: s, pixelSize: pixelSize)

    // 4. Sparkles
    drawSparkle(
        ctx: ctx,
        center: CGPoint(x: s * 0.76, y: s * 0.79),
        outerR: s * 0.055,
        innerR: s * 0.017,
        alpha: 0.95
    )

    if pixelSize >= 48 {
        drawSparkle(
            ctx: ctx,
            center: CGPoint(x: s * 0.28, y: s * 0.78),
            outerR: s * 0.030,
            innerR: s * 0.010,
            alpha: 0.60
        )
    }

    if pixelSize >= 256 {
        drawSparkle(
            ctx: ctx,
            center: CGPoint(x: s * 0.82, y: s * 0.48),
            outerR: s * 0.020,
            innerR: s * 0.006,
            alpha: 0.40
        )
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// MARK: - Paste Mark Drawing

func drawPasteMark(ctx: CGContext, size s: CGFloat, pixelSize: Int) {
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.018),
        blur: s * 0.045,
        color: CGColor(red: 0.02, green: 0.08, blue: 0.14, alpha: 0.38)
    )

    let board = CGRect(x: s * 0.25, y: s * 0.22, width: s * 0.50, height: s * 0.56)
    let boardPath = CGPath(
        roundedRect: board,
        cornerWidth: s * 0.070,
        cornerHeight: s * 0.070,
        transform: nil
    )
    ctx.setFillColor(CGColor(red: 0.94, green: 0.99, blue: 1.00, alpha: 1.0))
    ctx.addPath(boardPath)
    ctx.fillPath()

    ctx.restoreGState()

    let clip = CGRect(x: s * 0.38, y: s * 0.72, width: s * 0.24, height: s * 0.105)
    let clipPath = CGPath(
        roundedRect: clip,
        cornerWidth: s * 0.040,
        cornerHeight: s * 0.040,
        transform: nil
    )
    ctx.setFillColor(CGColor(red: 0.80, green: 0.96, blue: 1.00, alpha: 1.0))
    ctx.addPath(clipPath)
    ctx.fillPath()

    ctx.setStrokeColor(CGColor(red: 0.03, green: 0.34, blue: 0.54, alpha: 0.92))
    ctx.setLineWidth(max(1.0, s * 0.025))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    if pixelSize >= 64 {
        drawLine(ctx: ctx, from: CGPoint(x: s * 0.35, y: s * 0.61), to: CGPoint(x: s * 0.65, y: s * 0.61))
        drawLine(ctx: ctx, from: CGPoint(x: s * 0.35, y: s * 0.51), to: CGPoint(x: s * 0.56, y: s * 0.51))
    }

    let cursor = CGMutablePath()
    cursor.move(to: CGPoint(x: s * 0.40, y: s * 0.39))
    cursor.addLine(to: CGPoint(x: s * 0.50, y: s * 0.29))
    cursor.addLine(to: CGPoint(x: s * 0.67, y: s * 0.47))
    cursor.addLine(to: CGPoint(x: s * 0.57, y: s * 0.48))
    cursor.addLine(to: CGPoint(x: s * 0.62, y: s * 0.61))
    ctx.addPath(cursor)
    ctx.strokePath()
}

func drawLine(ctx: CGContext, from: CGPoint, to: CGPoint) {
    let path = CGMutablePath()
    path.move(to: from)
    path.addLine(to: to)
    ctx.addPath(path)
    ctx.strokePath()
}

// MARK: - Sparkle Drawing

func drawSparkle(
    ctx: CGContext,
    center: CGPoint,
    outerR: CGFloat,
    innerR: CGFloat,
    alpha: CGFloat
) {
    ctx.saveGState()

    // Glow halo (shadow on the fill)
    ctx.setShadow(
        offset: .zero,
        blur: outerR * 0.9,
        color: CGColor(red: 0.65, green: 0.78, blue: 1.0, alpha: alpha * 0.55)
    )

    // 4-pointed star path
    let path = CGMutablePath()
    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4.0 - .pi / 2.0
        let r = i % 2 == 0 ? outerR : innerR
        let pt = CGPoint(
            x: center.x + cos(angle) * r,
            y: center.y + sin(angle) * r
        )
        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
    }
    path.closeSubpath()

    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: alpha))
    ctx.addPath(path)
    ctx.fillPath()

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
