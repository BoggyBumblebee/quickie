#!/usr/bin/env swift

import AppKit
import Foundation

let fileManager = FileManager.default
let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let appIconDirectory = cwd.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset")
let statusIconDirectory = cwd.appendingPathComponent("Resources/Assets.xcassets/StatusIcon.imageset")
let sourceIconURL = cwd.appendingPathComponent("Resources/Assets/QuickieIcon.png")

struct Palette {
    static let coral = NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.34, alpha: 1.0)
    static let coralDark = NSColor(calibratedRed: 0.91, green: 0.31, blue: 0.24, alpha: 1.0)
    static let cream = NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.94, alpha: 1.0)
    static let paper = NSColor(calibratedRed: 0.97, green: 0.95, blue: 0.91, alpha: 1.0)
    static let line = NSColor(calibratedRed: 0.95, green: 0.67, blue: 0.62, alpha: 1.0)
    static let bolt = NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.25, alpha: 1.0)
    static let shadow = NSColor(calibratedWhite: 0.0, alpha: 0.12)
}

func drawRoundedRect(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func checklistImage(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: image.size).fill()

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.09
    let background = canvas.insetBy(dx: inset, dy: inset)
    drawRoundedRect(background, radius: size * 0.19, color: Palette.coral)

    let cardWidth = size * 0.50
    let cardHeight = size * 0.42
    let card = NSRect(
        x: size * 0.22,
        y: size * 0.28,
        width: cardWidth,
        height: cardHeight
    )

    let shadow = NSShadow()
    shadow.shadowColor = Palette.shadow
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.015)
    shadow.shadowBlurRadius = size * 0.03
    shadow.set()
    drawRoundedRect(card, radius: size * 0.05, color: Palette.cream)
    NSGraphicsContext.current?.saveGraphicsState()
    let clipPath = NSBezierPath(roundedRect: card, xRadius: size * 0.05, yRadius: size * 0.05)
    clipPath.addClip()
    drawRoundedRect(
        NSRect(x: card.minX, y: card.maxY - size * 0.09, width: card.width, height: size * 0.09),
        radius: 0,
        color: Palette.coralDark
    )
    NSGraphicsContext.current?.restoreGraphicsState()

    for row in 0..<3 {
        let y = card.maxY - size * 0.16 - CGFloat(row) * size * 0.10
        let box = NSRect(x: card.minX + size * 0.05, y: y - size * 0.03, width: size * 0.055, height: size * 0.055)
        drawRoundedRect(box, radius: size * 0.012, color: Palette.paper)

        let tick = NSBezierPath()
        tick.lineWidth = max(2.0, size * 0.010)
        tick.lineCapStyle = .round
        tick.lineJoinStyle = .round
        tick.move(to: NSPoint(x: box.minX + box.width * 0.22, y: box.minY + box.height * 0.50))
        tick.line(to: NSPoint(x: box.minX + box.width * 0.42, y: box.minY + box.height * 0.28))
        tick.line(to: NSPoint(x: box.maxX - box.width * 0.18, y: box.maxY - box.height * 0.24))
        Palette.coralDark.setStroke()
        tick.stroke()

        let lineRect = NSRect(x: box.maxX + size * 0.03, y: y - size * 0.018, width: size * 0.25, height: size * 0.036)
        drawRoundedRect(lineRect, radius: size * 0.015, color: Palette.line)
    }

    let boltRect = NSRect(x: size * 0.62, y: size * 0.30, width: size * 0.18, height: size * 0.25)
    let bolt = NSBezierPath()
    bolt.move(to: NSPoint(x: boltRect.minX + boltRect.width * 0.55, y: boltRect.maxY))
    bolt.line(to: NSPoint(x: boltRect.minX + boltRect.width * 0.15, y: boltRect.midY + boltRect.height * 0.10))
    bolt.line(to: NSPoint(x: boltRect.midX, y: boltRect.midY + boltRect.height * 0.10))
    bolt.line(to: NSPoint(x: boltRect.minX + boltRect.width * 0.30, y: boltRect.minY))
    bolt.line(to: NSPoint(x: boltRect.maxX, y: boltRect.midY - boltRect.height * 0.10))
    bolt.line(to: NSPoint(x: boltRect.midX + boltRect.width * 0.02, y: boltRect.midY - boltRect.height * 0.10))
    bolt.close()
    Palette.bolt.setFill()
    bolt.fill()

    image.unlockFocus()
    return image
}

func statusTemplateImage(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: image.size).fill()

    let stroke = NSBezierPath()
    stroke.lineWidth = max(1.5, size * 0.10)
    stroke.lineCapStyle = .round
    stroke.lineJoinStyle = .round

    let left = size * 0.12
    let right = size * 0.72
    let checkX = size * 0.14
    let firstY = size * 0.72
    let rowGap = size * 0.24

    for row in 0..<3 {
        let y = firstY - CGFloat(row) * rowGap

        stroke.move(to: NSPoint(x: checkX, y: y - size * 0.02))
        stroke.line(to: NSPoint(x: checkX + size * 0.08, y: y - size * 0.10))
        stroke.line(to: NSPoint(x: checkX + size * 0.19, y: y + size * 0.06))

        stroke.move(to: NSPoint(x: left + size * 0.18, y: y))
        stroke.line(to: NSPoint(x: right, y: y))
    }

    NSColor.black.setStroke()
    stroke.stroke()

    let bolt = NSBezierPath()
    let boltRect = NSRect(x: size * 0.60, y: size * 0.10, width: size * 0.24, height: size * 0.34)
    bolt.move(to: NSPoint(x: boltRect.minX + boltRect.width * 0.58, y: boltRect.maxY))
    bolt.line(to: NSPoint(x: boltRect.minX + boltRect.width * 0.18, y: boltRect.midY + boltRect.height * 0.08))
    bolt.line(to: NSPoint(x: boltRect.midX, y: boltRect.midY + boltRect.height * 0.08))
    bolt.line(to: NSPoint(x: boltRect.minX + boltRect.width * 0.32, y: boltRect.minY))
    bolt.line(to: NSPoint(x: boltRect.maxX, y: boltRect.midY - boltRect.height * 0.08))
    bolt.line(to: NSPoint(x: boltRect.midX + boltRect.width * 0.02, y: boltRect.midY - boltRect.height * 0.08))
    bolt.close()
    NSColor.black.setFill()
    bolt.fill()

    image.unlockFocus()
    image.isTemplate = true
    return image
}

func pngData(from image: NSImage, size: CGFloat) -> Data? {
    let targetImage = NSImage(size: NSSize(width: size, height: size))
    targetImage.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    targetImage.unlockFocus()

    guard let tiff = targetImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else {
        return nil
    }

    return bitmap.representation(using: .png, properties: [:])
}

let appIconBase = checklistImage(size: 1024)
let appIconSizes = [16, 32, 64, 128, 256, 512, 1024]

for size in appIconSizes {
    let fileURL = appIconDirectory.appendingPathComponent("AppIcon-\(size).png")
    guard let data = pngData(from: appIconBase, size: CGFloat(size)) else {
        fatalError("Could not render AppIcon-\(size).png")
    }
    try data.write(to: fileURL)
}

guard let sourcePNG = pngData(from: appIconBase, size: 1024) else {
    fatalError("Could not render QuickieIcon.png")
}
try sourcePNG.write(to: sourceIconURL)

let statusBase = statusTemplateImage(size: 36)
let statusSizes: [(CGFloat, String)] = [(18, "StatusIcon.png"), (36, "StatusIcon@2x.png")]
for (size, filename) in statusSizes {
    let fileURL = statusIconDirectory.appendingPathComponent(filename)
    guard let data = pngData(from: statusBase, size: size) else {
        fatalError("Could not render \(filename)")
    }
    try data.write(to: fileURL)
}

print("Generated Quickie app and status bar icons.")
