#!/usr/bin/env swift
//
// generate-icon.swift
// Generates the SuperPaste app icon at all required macOS asset catalog sizes.
//
// Usage: swift scripts/generate-icon.swift
//

import AppKit

let outputDir = "SuperPaste/Resources/Assets.xcassets/AppIcon.appiconset"

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

    // ────────────────────────────────────────────
    // 1. Background Gradient
    // ────────────────────────────────────────────
    let cs = CGColorSpaceCreateDeviceRGB()

    let bgColors = [
        CGColor(red: 0.11, green: 0.05, blue: 0.35, alpha: 1.0),   // deep violet-indigo
        CGColor(red: 0.16, green: 0.22, blue: 0.62, alpha: 1.0),   // royal blue
        CGColor(red: 0.22, green: 0.42, blue: 0.92, alpha: 1.0),   // bright blue
    ] as CFArray

    if let bg = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0.0, 0.50, 1.0]) {
        ctx.drawLinearGradient(
            bg,
            start: CGPoint(x: 0, y: 0),                // bottom-left
            end:   CGPoint(x: s, y: s),                 // top-right
            options: [.drawsAfterEndLocation, .drawsBeforeStartLocation]
        )
    }

    // ────────────────────────────────────────────
    // 2. Subtle Center Glow (adds depth)
    // ────────────────────────────────────────────
    let glowColors = [
        CGColor(red: 0.30, green: 0.42, blue: 1.0, alpha: 0.18),
        CGColor(red: 0.30, green: 0.42, blue: 1.0, alpha: 0.0),
    ] as CFArray
    if let glow = CGGradient(colorsSpace: cs, colors: glowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: s * 0.50, y: s * 0.44),
            startRadius: 0,
            endCenter:   CGPoint(x: s * 0.50, y: s * 0.44),
            endRadius:   s * 0.52,
            options: []
        )
    }

    // ────────────────────────────────────────────
    // 3. The "V" — bold stroked path with round caps
    // ────────────────────────────────────────────
    ctx.saveGState()

    // Drop shadow behind V for depth
    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.012),
        blur: s * 0.035,
        color: CGColor(red: 0.02, green: 0.02, blue: 0.12, alpha: 0.45)
    )

    let vPath = CGMutablePath()
    vPath.move(to:    CGPoint(x: s * 0.22, y: s * 0.76))   // top-left arm
    vPath.addLine(to: CGPoint(x: s * 0.50, y: s * 0.22))   // bottom center
    vPath.addLine(to: CGPoint(x: s * 0.78, y: s * 0.76))   // top-right arm

    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
    ctx.setLineWidth(s * 0.095)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(vPath)
    ctx.strokePath()

    ctx.restoreGState()

    // ────────────────────────────────────────────
    // 4. Sparkles
    // ────────────────────────────────────────────

    // Primary sparkle — top-right, above the V's right arm
    drawSparkle(
        ctx: ctx,
        center: CGPoint(x: s * 0.78, y: s * 0.84),
        outerR: s * 0.058,
        innerR: s * 0.017,
        alpha: 0.95
    )

    // Secondary sparkle — top-left, smaller
    if pixelSize >= 48 {
        drawSparkle(
            ctx: ctx,
            center: CGPoint(x: s * 0.24, y: s * 0.86),
            outerR: s * 0.032,
            innerR: s * 0.010,
            alpha: 0.60
        )
    }

    // Tiny tertiary — right side, mid-height (large sizes only)
    if pixelSize >= 256 {
        drawSparkle(
            ctx: ctx,
            center: CGPoint(x: s * 0.86, y: s * 0.56),
            outerR: s * 0.020,
            innerR: s * 0.006,
            alpha: 0.40
        )
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
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
