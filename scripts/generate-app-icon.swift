#!/usr/bin/env swift

import Foundation
import AppKit
import SwiftUI

// Import the FrownyFaceLogo from the main app
// We'll recreate a minimal version here for icon generation

// MARK: - Logo Mood
enum LogoMood {
    case neutral
}

// MARK: - Mouth Shapes
struct FrownArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY + rect.height * 0.18
        let radius = rect.width * 0.22
        path.addArc(
            center: CGPoint(x: cx, y: cy + radius * 0.6),
            radius: radius,
            startAngle: .degrees(-160),
            endAngle: .degrees(-20),
            clockwise: false
        )
        return path
    }
}

// MARK: - FrownyFaceLogo (simplified for icon generation)
struct FrownyFaceLogo: View {
    var size: CGFloat = 1024
    let mood: LogoMood = .neutral
    
    private let brandColor = Color(red: 0.2, green: 0.6, blue: 1.0) // G-Rump blue
    
    var body: some View {
        ZStack {
            faceCircle
            eyesView
            mouthView
        }
        .frame(width: size, height: size)
        .background(Color.clear)
    }
    
    @ViewBuilder
    private var faceCircle: some View {
        let borderGradient = LinearGradient(
            colors: [brandColor, brandColor.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        Circle()
            .fill(Color.white)
            .overlay(
                Circle()
                    .stroke(borderGradient, lineWidth: size * 0.05)
            )
            .shadow(color: brandColor.opacity(0.18), radius: size * 0.18, y: size * 0.06)
    }
    
    @ViewBuilder
    private var eyesView: some View {
        Circle()
            .fill(brandColor)
            .frame(width: size * 0.15, height: size * 0.15)
            .offset(x: -size * 0.17, y: -size * 0.1)
        Circle()
            .fill(brandColor)
            .frame(width: size * 0.15, height: size * 0.15)
            .offset(x: size * 0.17, y: -size * 0.1)
    }
    
    @ViewBuilder
    private var mouthView: some View {
        FrownArc()
            .stroke(brandColor, style: StrokeStyle(lineWidth: size * 0.055, lineCap: .round))
            .frame(width: size, height: size)
    }
}

// MARK: - App Icon View (macOS icon grid)
// Apple's macOS icon grid: on a 1024pt canvas the icon is an 824x824 squircle
// centered with ~100pt transparent margins on each side. Rendering full-bleed
// makes the icon look oversized and square next to every other Dock icon.
struct AppIconView: View {
    var size: CGFloat = 1024

    var body: some View {
        let squircleSize = size * (824.0 / 1024.0)
        let shape = RoundedRectangle(cornerRadius: squircleSize * 0.225, style: .continuous)
        ZStack {
            shape.fill(Color.white)
            FrownyFaceLogo(size: squircleSize * 0.72)
        }
        .frame(width: squircleSize, height: squircleSize)
        .clipShape(shape)
        .shadow(color: Color.black.opacity(0.25), radius: size * 0.012, y: size * 0.008)
        .frame(width: size, height: size)
    }
}

// MARK: - Icon Generator
class IconGenerator {

    /// Generate an icon at exactly `pixelSize` x `pixelSize` pixels (1x scale).
    static func generateIcon(pixelSize: Int) -> NSImage? {
        let size = CGFloat(pixelSize)
        let logo = AppIconView(size: size)

        let hostingView = NSHostingView(rootView: logo)
        hostingView.frame = CGRect(x: 0, y: 0, width: size, height: size)
        hostingView.layoutSubtreeIfNeeded()
        
        // Create a bitmap at exactly the requested pixel dimensions (1x scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        
        // Set the rep size to match pixel size (1x scale — no Retina doubling)
        rep.size = NSSize(width: pixelSize, height: pixelSize)
        
        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = ctx
        
        // Clear to transparent
        NSColor.clear.set()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        
        // Render the view
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
        
        NSGraphicsContext.restoreGraphicsState()
        
        let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
        image.addRepresentation(rep)
        return image
    }
    
    static func saveImage(_ image: NSImage, to path: String) -> Bool {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return false
        }
        
        do {
            try pngData.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            print("Failed to save image to \(path): \(error)")
            return false
        }
    }
}

// MARK: - Main Execution

// macOS App Icon slots: (point size, scale, required pixel size)
// 16x16 @1x=16, @2x=32
// 32x32 @1x=32, @2x=64
// 128x128 @1x=128, @2x=256
// 256x256 @1x=256, @2x=512
// 512x512 @1x=512, @2x=1024

struct IconSlot {
    let pointSize: Int
    let scale: Int
    var pixelSize: Int { pointSize * scale }
    var filename: String {
        if scale == 1 {
            return "icon_\(pointSize)x\(pointSize).png"
        }
        return "icon_\(pointSize)x\(pointSize)@2x.png"
    }
}

let slots: [IconSlot] = [
    IconSlot(pointSize: 16, scale: 1),
    IconSlot(pointSize: 16, scale: 2),
    IconSlot(pointSize: 32, scale: 1),
    IconSlot(pointSize: 32, scale: 2),
    IconSlot(pointSize: 128, scale: 1),
    IconSlot(pointSize: 128, scale: 2),
    IconSlot(pointSize: 256, scale: 1),
    IconSlot(pointSize: 256, scale: 2),
    IconSlot(pointSize: 512, scale: 1),
    IconSlot(pointSize: 512, scale: 2),
]

let outputDir = "Sources/GRump/Resources/Assets.xcassets/AppIcon.appiconset"

print("Generating G-Rump app icons (correct pixel sizes)...")

for slot in slots {
    print("Generating \(slot.filename) (\(slot.pixelSize)x\(slot.pixelSize) px)...")
    
    if let image = IconGenerator.generateIcon(pixelSize: slot.pixelSize) {
        let path = "\(outputDir)/\(slot.filename)"
        
        if IconGenerator.saveImage(image, to: path) {
            print("✅ Saved \(slot.filename) — \(slot.pixelSize)x\(slot.pixelSize) pixels")
        } else {
            print("❌ Failed to save \(slot.filename)")
        }
    } else {
        print("❌ Failed to generate \(slot.filename)")
    }
}

// Generate Contents.json
let contentsJSON = """
{
  "images": [
    {"filename": "icon_16x16.png", "idiom": "mac", "scale": "1x", "size": "16x16"},
    {"filename": "icon_16x16@2x.png", "idiom": "mac", "scale": "2x", "size": "16x16"},
    {"filename": "icon_32x32.png", "idiom": "mac", "scale": "1x", "size": "32x32"},
    {"filename": "icon_32x32@2x.png", "idiom": "mac", "scale": "2x", "size": "32x32"},
    {"filename": "icon_128x128.png", "idiom": "mac", "scale": "1x", "size": "128x128"},
    {"filename": "icon_128x128@2x.png", "idiom": "mac", "scale": "2x", "size": "128x128"},
    {"filename": "icon_256x256.png", "idiom": "mac", "scale": "1x", "size": "256x256"},
    {"filename": "icon_256x256@2x.png", "idiom": "mac", "scale": "2x", "size": "256x256"},
    {"filename": "icon_512x512.png", "idiom": "mac", "scale": "1x", "size": "512x512"},
    {"filename": "icon_512x512@2x.png", "idiom": "mac", "scale": "2x", "size": "512x512"}
  ],
  "info": {"author": "xcode", "version": 1}
}
"""

let contentsPath = "\(outputDir)/Contents.json"
do {
    try contentsJSON.write(toFile: contentsPath, atomically: true, encoding: .utf8)
    print("✅ Updated Contents.json")
} catch {
    print("❌ Failed to write Contents.json: \(error)")
}

print("Icon generation complete!")
