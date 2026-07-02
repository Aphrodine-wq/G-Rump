import Foundation
import CoreGraphics
#if os(macOS)
import ScreenCaptureKit
#endif

/// Result of one capture tick. Sendable so it can cross back to the @MainActor engine —
/// the non-Sendable `CGImage` never leaves this actor.
enum CaptureResult: Sendable {
    case failed
    case unchanged(phash: UInt64)
    case changed(phash: UInt64, text: String)
}

/// Owns screen capture + perceptual hashing + OCR in a single isolation domain, so the
/// `CGImage` is created, hashed, and OCR'd here and only Sendable results escape.
actor ScreenCaptureService {

    /// Whether Screen Recording permission is currently granted.
    func permissionGranted() async -> Bool {
        #if os(macOS)
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    /// Capture the main display, hash it, and (only if visibly changed vs `previousHash`)
    /// OCR it. `changeThreshold` is the Hamming distance below which a frame is "unchanged".
    func captureFrame(previousHash: UInt64?, changeThreshold: Int = 4) async -> CaptureResult {
        #if os(macOS)
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return .failed }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            // Downscale for cheap OCR + hashing (half-ish resolution is plenty for text).
            config.width = max(display.width / 2, 640)
            config.height = max(display.height / 2, 400)
            config.showsCursor = false

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let phash = PerceptualHash.hash(cgImage)

            if let previousHash, PerceptualHash.distance(phash, previousHash) < changeThreshold {
                return .unchanged(phash: phash)
            }

            let text = OCRService.recognizeText(in: cgImage)
            return .changed(phash: phash, text: text)
        } catch {
            return .failed
        }
        #else
        return .failed
        #endif
    }
}
