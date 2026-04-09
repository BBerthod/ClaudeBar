#!/usr/bin/env swift

// Generates ClaudeBar.iconset PNG files for all required macOS app icon sizes.
// Run with: swift scripts/generate_icon.swift
// Then: iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns

import AppKit
import Foundation

func makeIconImage(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    // Rounded rect clip
    let cornerRadius = s * 0.225
    let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                      cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // Background gradient: deep indigo → violet
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradientColors = [
        CGColor(red: 0.09, green: 0.09, blue: 0.30, alpha: 1.0),
        CGColor(red: 0.28, green: 0.08, blue: 0.48, alpha: 1.0)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0, 1]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: s),
                               end: CGPoint(x: s, y: 0),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    // Subtle inner shadow / depth ring
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
    ctx.setLineWidth(s * 0.015)
    let innerPath = CGPath(roundedRect: CGRect(x: s * 0.015, y: s * 0.015,
                                               width: s * 0.97, height: s * 0.97),
                           cornerWidth: cornerRadius - s * 0.015,
                           cornerHeight: cornerRadius - s * 0.015, transform: nil)
    ctx.addPath(innerPath)
    ctx.strokePath()

    // Draw brain SF Symbol
    let symbolPt = s * 0.50
    let config = NSImage.SymbolConfiguration(pointSize: symbolPt, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "brain", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let symbolSize = symbol.size
        let ox = (s - symbolSize.width) / 2
        let oy = (s - symbolSize.height) / 2
        symbol.draw(in: NSRect(x: ox, y: oy, width: symbolSize.width, height: symbolSize.height),
                    from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("  ✗ Failed to encode \(path)")
        return
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("  ✓ \(path)")
    } catch {
        print("  ✗ \(path): \(error)")
    }
}

// Required iconset structure
let iconsetDir = "Resources/AppIcon.iconset"
let fm = FileManager.default
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true, attributes: nil)

let entries: [(name: String, size: Int)] = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]

print("Generating ClaudeBar icon...")
for entry in entries {
    let image = makeIconImage(size: entry.size)
    savePNG(image, to: "\(iconsetDir)/\(entry.name)")
}
print("Done. Run: iconutil -c icns \(iconsetDir) -o Resources/AppIcon.icns")
