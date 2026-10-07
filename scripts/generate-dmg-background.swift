#!/usr/bin/env swift
//
// generate-dmg-background.swift
// Draws the background for the DMG install window: a light canvas with a
// blue arrow pointing from the app icon (left) to the Applications alias
// (right) and a one-line instruction underneath.
//
// Light on purpose: Finder renders icon labels in dark text, which would be
// unreadable on the site's dark palette.
//
// Usage: swift scripts/generate-dmg-background.swift <output.tiff>
//
// Writes a multi-resolution TIFF (1x + 2x) so the window is sharp on Retina.
// Geometry must match the icon positions in scripts/release.sh.
//

import AppKit

let width = 600
let height = 400
// Finder icon centers (top-left origin) — keep in sync with release.sh.
let appCenterX: CGFloat = 150
let applicationsCenterX: CGFloat = 450
let iconCenterY: CGFloat = 185

let brandBlue = CGColor(red: 0.10, green: 0.50, blue: 0.95, alpha: 1.0)

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: generate-dmg-background.swift <output.tiff>\n".data(using: .utf8)!)
    exit(1)
}
let outputPath = CommandLine.arguments[1]

func render(scale: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width * scale,
        pixelsHigh: height * scale,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    // Point size stays 600x400 so Finder lays the 2x rep out at 1x geometry.
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    let w = CGFloat(width), h = CGFloat(height)

    // Soft vertical gradient.
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.97, green: 0.98, blue: 1.00, alpha: 1),
            CGColor(red: 0.91, green: 0.94, blue: 0.98, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])

    // Arrow between the two icons (CG origin is bottom-left).
    let y = h - iconCenterY
    let startX = appCenterX + 80
    let endX = applicationsCenterX - 80
    let headLength: CGFloat = 22
    let headHalfWidth: CGFloat = 16

    ctx.setStrokeColor(brandBlue)
    ctx.setLineWidth(6)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: startX, y: y))
    ctx.addLine(to: CGPoint(x: endX - headLength + 2, y: y))
    ctx.strokePath()

    ctx.setFillColor(brandBlue)
    ctx.move(to: CGPoint(x: endX, y: y))
    ctx.addLine(to: CGPoint(x: endX - headLength, y: y + headHalfWidth))
    ctx.addLine(to: CGPoint(x: endX - headLength, y: y - headHalfWidth))
    ctx.closePath()
    ctx.fillPath()

    // Instruction text.
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let title = NSAttributedString(
        string: "Drag SuperPaste into Applications to install",
        attributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 1),
            .paragraphStyle: paragraph,
        ]
    )
    title.draw(in: NSRect(x: 0, y: 70, width: w, height: 26))

    let subtitle = NSAttributedString(
        string: "Then open it from your Applications folder.",
        attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor(calibratedWhite: 0.40, alpha: 1),
            .paragraphStyle: paragraph,
        ]
    )
    subtitle.draw(in: NSRect(x: 0, y: 46, width: w, height: 20))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let image = NSImage(size: NSSize(width: width, height: height))
image.addRepresentation(render(scale: 1))
image.addRepresentation(render(scale: 2))

guard let tiff = image.tiffRepresentation(using: .lzw, factor: 0) else {
    FileHandle.standardError.write("failed to encode TIFF\n".data(using: .utf8)!)
    exit(1)
}
do {
    try tiff.write(to: URL(fileURLWithPath: outputPath))
} catch {
    FileHandle.standardError.write("failed to write \(outputPath): \(error)\n".data(using: .utf8)!)
    exit(1)
}
print("Wrote \(outputPath)")
