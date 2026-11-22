#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// MARK: - Nudge Moss macOS App Icon Generator
// Theme: Moss (tweakcn.com/themes/cmmi1gb4a000204jl8c300w9a)
// Deep warm dark bark squircle (#070503 -> #100d08) with #2f281b border,
// #495940 deep forest moss glow, and crisp sage-moss #AFBEA5 / #7F956A battery + lightning emblem.

func color(hex: UInt32, alpha: CGFloat = 1.0) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, alpha])!
}

/// Builds a smooth Apple-style superellipse / continuous rounded rect path.
func squirclePath(in rect: CGRect, cornerRadius: CGFloat) -> CGPath {
    let bezier = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    let path = CGMutablePath()
    var points = [NSPoint](repeating: .zero, count: 3)
    for i in 0..<bezier.elementCount {
        let type = bezier.element(at: i, associatedPoints: &points)
        switch type {
        case .moveTo:
            path.move(to: points[0])
        case .lineTo:
            path.addLine(to: points[0])
        case .curveTo:
            path.addCurve(to: points[2], control1: points[0], control2: points[1])
        case .closePath:
            path.closeSubpath()
        case .cubicCurveTo:
            path.addCurve(to: points[2], control1: points[0], control2: points[1])
        case .quadraticCurveTo:
            path.addQuadCurve(to: points[1], control: points[0])
        @unknown default:
            break
        }
    }
    return path
}

func renderIcon(pixelSize: Int) -> CGImage? {
    let size = CGFloat(pixelSize)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // Clear canvas
    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

    // Standard macOS Big Sur/Sonoma icon inset (~10% padding on each side)
    let inset = size * 0.097
    let iconRect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let cornerRadius = iconRect.width * 0.225
    let bgPath = squirclePath(in: iconRect, cornerRadius: cornerRadius)

    // 1. Subtle outer drop shadow for the squircle
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.015),
        blur: size * 0.04,
        color: CGColor(colorSpace: colorSpace, components: [0, 0, 0, 0.48])
    )
    ctx.addPath(bgPath)
    ctx.setFillColor(color(hex: 0x070503))
    ctx.fillPath()
    ctx.restoreGState()

    // 2. Clip inside squircle for interior gradients & glow
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    // Deep warm dark bark vertical background gradient (#100d08 -> #070503)
    let bgGradientColors = [color(hex: 0x100d08), color(hex: 0x070503)] as CFArray
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgGradientColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            bgGradient,
            start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
            end: CGPoint(x: iconRect.midX, y: iconRect.minY),
            options: []
        )
    }

    // Subtle warm top sheen
    let sheenColors = [color(hex: 0xAFBEA5, alpha: 0.06), color(hex: 0xAFBEA5, alpha: 0.0)] as CFArray
    if let sheenGradient = CGGradient(colorsSpace: colorSpace, colors: sheenColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            sheenGradient,
            start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
            end: CGPoint(x: iconRect.midX, y: iconRect.midY + iconRect.height * 0.05),
            options: []
        )
    }

    // Ambient deep forest moss radial glow (#495940) behind the battery emblem
    let glowCenter = CGPoint(x: iconRect.midX, y: iconRect.midY)
    let glowColors = [
        color(hex: 0x495940, alpha: 0.48),
        color(hex: 0x495940, alpha: 0.18),
        color(hex: 0x495940, alpha: 0.0)
    ] as CFArray
    if let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 0.5, 1.0]) {
        ctx.drawRadialGradient(
            glowGradient,
            startCenter: glowCenter,
            startRadius: iconRect.width * 0.04,
            endCenter: glowCenter,
            endRadius: iconRect.width * 0.56,
            options: []
        )
    }

    // Subtle circular ring accent in forest moss
    let ringRadius = iconRect.width * 0.365
    let ringRect = CGRect(
        x: iconRect.midX - ringRadius,
        y: iconRect.midY - ringRadius,
        width: ringRadius * 2,
        height: ringRadius * 2
    )
    ctx.setStrokeColor(color(hex: 0x7F956A, alpha: 0.20))
    ctx.setLineWidth(max(1.0, size * 0.006))
    ctx.strokeEllipse(in: ringRect)

    // 3. Geometric Battery Frame (horizontal rounded pill + right terminal cap)
    let battWidth = iconRect.width * 0.58
    let battHeight = iconRect.height * 0.34
    let battX = iconRect.midX - battWidth * 0.53
    let battY = iconRect.midY - battHeight * 0.5
    let battRect = CGRect(x: battX, y: battY, width: battWidth, height: battHeight)
    let battCorner = battHeight * 0.24
    let battStroke = max(1.5, size * 0.026)

    // Battery interior dark bark glass fill
    let battPath = squirclePath(in: battRect, cornerRadius: battCorner)
    ctx.saveGState()
    ctx.addPath(battPath)
    ctx.setFillColor(color(hex: 0x0b0905, alpha: 0.88))
    ctx.fillPath()
    ctx.restoreGState()

    // 80% Charge level bar inside battery (signature Nudge 80% charge limit aesthetic)
    let barPadding = battStroke * 1.15
    let innerWidth = battRect.width - barPadding * 2
    let innerHeight = battRect.height - barPadding * 2
    let fillRect = CGRect(
        x: battRect.minX + barPadding,
        y: battRect.minY + barPadding,
        width: innerWidth * 0.78,
        height: innerHeight
    )
    let fillPath = squirclePath(in: fillRect, cornerRadius: max(1.0, battCorner * 0.52))
    ctx.saveGState()
    ctx.addPath(fillPath)
    ctx.clip()
    let barColors = [
        color(hex: 0xAFBEA5, alpha: 0.32),
        color(hex: 0x7F956A, alpha: 0.16)
    ] as CFArray
    if let barGradient = CGGradient(colorsSpace: colorSpace, colors: barColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            barGradient,
            start: CGPoint(x: fillRect.minX, y: fillRect.maxY),
            end: CGPoint(x: fillRect.maxX, y: fillRect.minY),
            options: []
        )
    }
    ctx.restoreGState()

    // Crisp sage-moss battery outer border with deep forest moss glow
    ctx.saveGState()
    ctx.setShadow(
        offset: .zero,
        blur: size * 0.028,
        color: color(hex: 0x7F956A, alpha: 0.50)
    )
    ctx.addPath(battPath)
    ctx.setStrokeColor(color(hex: 0xAFBEA5, alpha: 0.96))
    ctx.setLineWidth(battStroke)
    ctx.strokePath()
    ctx.restoreGState()

    // Battery positive terminal cap on the right
    let capWidth = iconRect.width * 0.048
    let capHeight = battHeight * 0.42
    let capRect = CGRect(
        x: battRect.maxX + battStroke * 0.75,
        y: iconRect.midY - capHeight * 0.5,
        width: capWidth,
        height: capHeight
    )
    let capPath = squirclePath(in: capRect, cornerRadius: capWidth * 0.45)
    ctx.saveGState()
    ctx.setShadow(
        offset: .zero,
        blur: size * 0.02,
        color: color(hex: 0x7F956A, alpha: 0.45)
    )
    ctx.addPath(capPath)
    ctx.setFillColor(color(hex: 0xAFBEA5, alpha: 0.96))
    ctx.fillPath()
    ctx.restoreGState()

    // 4. Crisp Geometric Sage-Moss Lightning Bolt Emblem centered over the battery
    let cx = battRect.midX + size * 0.005
    let cy = battRect.midY
    let boltScale = iconRect.width * 0.44

    let boltPath = CGMutablePath()
    // Coordinates in normalized [-0.5, 0.5] space, flipped for CG bottom-left origin
    let boltPoints: [(CGFloat, CGFloat)] = [
        (0.08,  0.52),  // Top apex
        (-0.28, 0.01),  // Mid-left outer corner
        (-0.02, 0.01),  // Mid-left inner notch
        (-0.14, -0.52), // Bottom apex
        (0.28, -0.02),  // Mid-right outer corner
        (0.02, -0.02)   // Mid-right inner notch
    ]
    if let first = boltPoints.first {
        boltPath.move(to: CGPoint(x: cx + first.0 * boltScale, y: cy + first.1 * boltScale))
        for pt in boltPoints.dropFirst() {
            boltPath.addLine(to: CGPoint(x: cx + pt.0 * boltScale, y: cy + pt.1 * boltScale))
        }
        boltPath.closeSubpath()
    }

    // Dark bark cutout halo behind bolt so it punches cleanly through the battery border
    ctx.saveGState()
    ctx.addPath(boltPath)
    ctx.setStrokeColor(color(hex: 0x070503, alpha: 0.94))
    ctx.setLineWidth(max(1.5, size * 0.032))
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Crisp sage-moss (#AFBEA5 -> #7F956A) lightning bolt fill with subtle moss glow
    ctx.saveGState()
    ctx.setShadow(
        offset: .zero,
        blur: size * 0.042,
        color: color(hex: 0x7F956A, alpha: 0.72)
    )
    ctx.addPath(boltPath)
    ctx.clip()
    let boltColors = [
        color(hex: 0xD2DDD0), // crisp pale sage highlight tip
        color(hex: 0xAFBEA5), // primary Moss sage
        color(hex: 0x7F956A)  // deep organic moss base
    ] as CFArray
    if let boltGradient = CGGradient(colorsSpace: colorSpace, colors: boltColors, locations: [0.0, 0.45, 1.0]) {
        ctx.drawLinearGradient(
            boltGradient,
            start: CGPoint(x: cx, y: cy + boltScale * 0.55),
            end: CGPoint(x: cx, y: cy - boltScale * 0.55),
            options: []
        )
    }
    ctx.restoreGState()

    // Restore clip
    ctx.restoreGState()

    // 5. Subtle warm bark rim border (#2f281b) around squircle
    let borderRect = iconRect.insetBy(dx: max(0.5, size * 0.004), dy: max(0.5, size * 0.004))
    let borderPath = squirclePath(in: borderRect, cornerRadius: cornerRadius - size * 0.004)
    ctx.saveGState()
    ctx.addPath(borderPath)
    ctx.setStrokeColor(color(hex: 0x2f281b, alpha: 0.95))
    ctx.setLineWidth(max(1.0, size * 0.010))
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()
}

func savePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    try data.write(to: url)
}

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let resourcesDir = cwd.appendingPathComponent("Resources", isDirectory: true)
let iconsetDir = resourcesDir.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let icnsURL = resourcesDir.appendingPathComponent("AppIcon.icns")

try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
if fm.fileExists(atPath: iconsetDir.path) {
    try fm.removeItem(at: iconsetDir)
}
try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for entry in entries {
    guard let img = renderIcon(pixelSize: entry.pixels) else {
        fputs("Error: failed to render \(entry.name)\n", stderr)
        exit(1)
    }
    try savePNG(img, to: iconsetDir.appendingPathComponent(entry.name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    fputs("Error: iconutil failed with status \(process.terminationStatus)\n", stderr)
    exit(1)
}

// Clean up intermediate iconset directory so Resources/ stays spotless
try? fm.removeItem(at: iconsetDir)
print("Generated \(icnsURL.path)")
