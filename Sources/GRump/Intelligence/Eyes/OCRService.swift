import Foundation
import Vision
import CoreGraphics

/// Fast on-device OCR for Eyes. Uses Vision's `.fast` recognition (lower latency than the
/// `.accurate` path in ContinuityScanner) since ambient capture runs every ~10s.
enum OCRService {

    /// Recognize text in a frame. Returns "" on failure. `maxChars` caps stored length.
    static func recognizeText(in image: CGImage, maxChars: Int = 6000) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }

        guard let observations = request.results as? [VNRecognizedTextObservation] else { return "" }
        var text = ""
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            text += candidate.string + "\n"
            if text.count >= maxChars { break }
        }
        return String(text.prefix(maxChars))
    }
}
