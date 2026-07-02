import Foundation
import Vision
import CoreImage
#if os(macOS)
import AppKit
import AVFoundation
#endif
import SwiftUI

// MARK: - Continuity Scanner Service
//
// Enables scanning documents from iOS device camera directly into G-Rump on Mac.
// Uses Continuity Camera for seamless cross-device document capture.
// VNDocumentCameraViewController is iOS-only; macOS uses AVCaptureSession.
//

@MainActor
final class ContinuityScannerService: NSObject, ObservableObject {

    static let shared = ContinuityScannerService()

    @Published var isScanningAvailable = false
    @Published var isScanning = false
    @Published var scannedDocuments: [ScannedDocument] = []
    @Published var scannerState: ScannerState = .idle

    private override init() {
        super.init()
        checkScanningAvailability()
    }

    // MARK: - Availability Check

    private func checkScanningAvailability() {
        #if os(macOS)
        if #available(macOS 13.0, *) {
            isScanningAvailable = true
        }
        #endif
    }

    // MARK: - Document Scanning

    func startDocumentScanning() async throws -> ScannedDocument? {
        #if os(macOS)
        guard isScanningAvailable else {
            throw ScannerError.notAvailable
        }
        isScanning = true
        scannerState = .scanning

        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo

        // Find camera — prefer Continuity Camera (external iPhone), fall back to built-in
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        guard let camera = discoverySession.devices.first else {
            isScanning = false
            scannerState = .idle
            throw ScannerError.cameraNotFound
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: camera)
        } catch {
            isScanning = false
            scannerState = .idle
            throw ScannerError.scanningFailed(error)
        }

        guard captureSession.canAddInput(input) else {
            isScanning = false
            scannerState = .idle
            throw ScannerError.scanningFailed(NSError(domain: "ContinuityScanner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add camera input"]))
        }
        captureSession.addInput(input)

        let photoOutput = AVCapturePhotoOutput()
        guard captureSession.canAddOutput(photoOutput) else {
            isScanning = false
            scannerState = .idle
            throw ScannerError.scanningFailed(NSError(domain: "ContinuityScanner", code: -2, userInfo: [NSLocalizedDescriptionKey: "Cannot add photo output"]))
        }
        captureSession.addOutput(photoOutput)

        // Start capture on background thread
        let sessionQueue = DispatchQueue(label: "com.grump.scanner.session")
        sessionQueue.async {
            captureSession.startRunning()
        }

        // Show camera preview window and wait for capture
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill

        let document: ScannedDocument? = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let cameraWindow = CameraWindow(
                    previewLayer: previewLayer,
                    captureSession: captureSession,
                    photoOutput: photoOutput
                )
                cameraWindow.onDocumentCaptured = { doc in
                    continuation.resume(returning: doc)
                }
                cameraWindow.onCancelled = {
                    continuation.resume(returning: nil)
                }
                cameraWindow.center()
                cameraWindow.makeKeyAndOrderFront(nil)
            }
        }

        isScanning = false
        scannerState = document != nil ? .completed : .idle

        if let doc = document {
            scannedDocuments.insert(doc, at: 0)
        }

        return document
        #else
        throw ScannerError.notAvailable
        #endif
    }

    // MARK: - Document Processing

    /// Process scanned document with OCR
    func processDocument(_ image: CGImage) async throws -> ProcessedDocument {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "en-GB", "zh-Hans", "zh-Hant", "ja", "ko", "es", "fr", "de", "it"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
            throw ScannerError.noTextFound
        }

        var recognizedText = ""
        var confidence: Float = 0

        for observation in observations {
            guard let topCandidate = observation.topCandidates(1).first else { continue }
            recognizedText += topCandidate.string + "\n"
            confidence += topCandidate.confidence
        }

        confidence /= Float(observations.count)

        // Detect code blocks and diagrams
        let codeBlocks = extractCodeBlocks(from: recognizedText)
        let diagrams = detectDiagrams(in: image)

        return ProcessedDocument(
            text: recognizedText,
            confidence: confidence,
            codeBlocks: codeBlocks,
            diagrams: diagrams,
            timestamp: Date()
        )
    }

    // MARK: - Text Analysis

    private func extractCodeBlocks(from text: String) -> [CodeBlock] {
        var codeBlocks: [CodeBlock] = []

        // Pattern to detect code blocks
        let codeBlockPattern = #"(?s)(```[\s\S]*?```|`[^`]+`)"#

        let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: [])
        let matches = regex?.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))

        for match in matches ?? [] {
            if let range = Range(match.range, in: text) {
                let codeText = String(text[range])
                let language = detectLanguage(for: codeText)

                codeBlocks.append(CodeBlock(
                    text: codeText,
                    language: language,
                    range: match.range
                ))
            }
        }

        return codeBlocks
    }

    private func detectLanguage(for code: String) -> String {
        let patterns: [String: String] = [
            "func ": "swift",
            "def ": "python",
            "function ": "javascript",
            "public class": "java",
            "fn ": "rust",
            "go func": "go",
            "async def": "python",
            "@Component": "typescript",
            "import React": "javascript",
            "#include": "cpp",
            "using namespace": "cpp",
            "package main": "go",
            "module ": "rust",
            "class ": "java",
            "interface ": "typescript"
        ]

        for (pattern, language) in patterns {
            if code.contains(pattern) {
                return language
            }
        }

        return "text"
    }

    private func detectDiagrams(in image: CGImage) -> [Diagram] {
        var diagrams: [Diagram] = []

        // Use Vision to detect rectangles (potential diagrams/flowcharts)
        let request = VNDetectRectanglesRequest { request, _ in
            guard let observations = request.results as? [VNRectangleObservation] else { return }

            for observation in observations {
                if observation.confidence > 0.8 {
                    // Extract the rectangle region
                    let diagram = Diagram(
                        type: .flowchart,
                        boundingBox: observation.boundingBox,
                        confidence: observation.confidence
                    )
                    diagrams.append(diagram)
                }
            }
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])

        return diagrams
    }

    // MARK: - Integration with G-Rump

    /// Send scanned document to G-Rump for processing
    func sendToGRump(_ document: ScannedDocument) {
        NotificationCenter.default.post(
            name: .documentScanned,
            object: nil,
            userInfo: ["document": document]
        )
    }
}

// VNDocumentCameraViewControllerDelegate would be used on iOS
// For macOS, scanning is done via AVCaptureSession (Continuity Camera)

// MARK: - Supporting Types

struct ScannedDocument: Identifiable {
    let id = UUID()
    let image: CGImage
    let processed: ProcessedDocument
    let pageCount: Int
    let scannedAt = Date()
}

struct ProcessedDocument {
    let text: String
    let confidence: Float
    let codeBlocks: [CodeBlock]
    let diagrams: [Diagram]
    let timestamp: Date
}

struct CodeBlock {
    let text: String
    let language: String
    let range: NSRange
}

struct Diagram {
    enum DiagramType {
        case flowchart
        case uml
        case wireframe
        case mindMap
        case unknown
    }

    let type: DiagramType
    let boundingBox: CGRect
    let confidence: Float
}

enum ScannerState {
    case idle
    case scanning
    case processing
    case completed
    case error(String)
}

enum ScannerError: LocalizedError {
    case notAvailable
    case cameraNotFound
    case scanningFailed(Error)
    case ocrFailed(Error)
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Document scanning is not available on this device"
        case .cameraNotFound:
            return "No camera found"
        case .scanningFailed(let error):
            return "Scanning failed: \(error.localizedDescription)"
        case .ocrFailed(let error):
            return "Text recognition failed: \(error.localizedDescription)"
        case .noTextFound:
            return "No text found in document"
        }
    }
}

// MARK: - Camera Window (macOS)

#if os(macOS)
class CameraWindow: NSWindow {

    var onDocumentCaptured: ((ScannedDocument) -> Void)?
    var onCancelled: (() -> Void)?

    init(previewLayer: AVCaptureVideoPreviewLayer, captureSession: AVCaptureSession, photoOutput: AVCapturePhotoOutput) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = "Document Scanner"
        level = .floating

        // Create preview view
        let previewView = NSView(frame: NSRect(x: 0, y: 40, width: 640, height: 480))
        previewView.layer = previewLayer
        previewView.wantsLayer = true

        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 520))
        containerView.addSubview(previewView)
        contentView = containerView

        // Add capture button
        let captureButton = NSButton(
            title: "Capture",
            target: self,
            action: #selector(capturePhoto)
        )
        captureButton.bezelStyle = .rounded
        captureButton.frame = NSRect(x: 330, y: 5, width: 100, height: 30)
        containerView.addSubview(captureButton)

        // Add cancel button
        let cancelButton = NSButton(
            title: "Cancel",
            target: self,
            action: #selector(cancelCapture)
        )
        cancelButton.bezelStyle = .rounded
        cancelButton.frame = NSRect(x: 210, y: 5, width: 100, height: 30)
        containerView.addSubview(cancelButton)

        // Store references
        self.captureSession = captureSession
        self.photoOutput = photoOutput
        self.previewLayer = previewLayer
    }

    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    @objc private func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput?.capturePhoto(with: settings, delegate: self)
    }

    @objc private func cancelCapture() {
        captureSession?.stopRunning()
        close()
        onCancelled?()
    }

    override func close() {
        captureSession?.stopRunning()
        super.close()
    }
}

extension CameraWindow: AVCapturePhotoCaptureDelegate {

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            GRumpLogger.capture.error("Photo capture error: \(error.localizedDescription)")
            captureSession?.stopRunning()
            close()
            onCancelled?()
            return
        }

        guard let imageData = photo.fileDataRepresentation(),
              let dataProvider = CGDataProvider(data: imageData as CFData),
              let image = CGImage(pngDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            captureSession?.stopRunning()
            close()
            onCancelled?()
            return
        }

        // Process the image
        Task {
            do {
                let processed = try await ContinuityScannerService.shared.processDocument(image)
                let scannedDocument = ScannedDocument(
                    image: image,
                    processed: processed,
                    pageCount: 1
                )

                DispatchQueue.main.async {
                    self.captureSession?.stopRunning()
                    self.close()
                    self.onDocumentCaptured?(scannedDocument)
                }

            } catch {
                DispatchQueue.main.async {
                    self.captureSession?.stopRunning()
                    self.close()
                    self.onCancelled?()
                }
            }
        }
    }
}
#endif

// MARK: - Notification Names

extension Notification.Name {
    static let documentScanned = Notification.Name("DocumentScanned")
}
