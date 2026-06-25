import Foundation
import CoreGraphics

#if canImport(AppKit)
import AppKit
#endif

/// 64-bit average perceptual hash (aHash) over a downscaled 8×8 grayscale of a frame.
/// Used to cheaply skip OCR when the screen hasn't visibly changed — the main perf lever
/// that keeps Eyes near-idle on a static screen.
enum PerceptualHash {

    /// Compute a 64-bit aHash for a CGImage. Returns 0 on failure (treated as "changed").
    static func hash(_ image: CGImage) -> UInt64 {
        let size = 8
        let bytesPerRow = size
        var pixels = [UInt8](repeating: 0, count: size * size)
        let colorSpace = CGColorSpaceCreateDeviceGray()

        guard let context = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return 0
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        let total = pixels.reduce(0) { $0 + Int($1) }
        let mean = UInt8(total / pixels.count)

        var bits: UInt64 = 0
        for (i, p) in pixels.enumerated() where p > mean {
            bits |= (UInt64(1) << UInt64(i))
        }
        return bits
    }

    /// Hamming distance between two hashes (0 = identical, 64 = maximally different).
    static func distance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }
}
