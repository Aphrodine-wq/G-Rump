import Foundation
#if canImport(CoreML)
import CoreML
#endif

// MARK: - Core ML Model Catalog

/// A downloadable Core ML model from HuggingFace Hub.
struct CoreMLModelCatalogEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let repoID: String
    let filename: String
    let sizeBytes: Int64
    let quantization: String
    let parameterCount: String
    let contextLength: Int
    let category: Category

    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    enum Category: String, CaseIterable {
        case apple = "Apple"
    }

    /// Recommended minimum RAM in GB for this model.
    var recommendedRAMGB: Int {
        let sizeGB = Double(sizeBytes) / 1_073_741_824.0
        return Int(ceil(sizeGB * 2.5))
    }
}

// MARK: - Download State

enum CoreMLDownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double, bytesReceived: Int64, totalBytes: Int64)
    case paused(bytesReceived: Int64, totalBytes: Int64)
    case downloaded
    case error(String)

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

// MARK: - Registry

@MainActor
final class CoreMLModelRegistryService: ObservableObject {

    @Published private(set) var downloadStates: [String: CoreMLDownloadState] = [:]
    @Published private(set) var systemRAMGB: Int = 8

    private var activeDownloadTasks: [String: Task<Void, Error>] = [:]
    private var resumeData: [String: Data] = [:]

    private var modelDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("GRump/Models", isDirectory: true)
    }

    // MARK: - Catalog

    static let catalog: [CoreMLModelCatalogEntry] = [
        // Apple's own models
        CoreMLModelCatalogEntry(
            id: "openelm-3b",
            name: "OpenELM 3B",
            description: "Apple's open-source efficient language model. Optimized for Apple Silicon.",
            repoID: "apple/OpenELM-3B",
            filename: "OpenELM-3B.mlpackage",
            sizeBytes: 1_800_000_000,
            quantization: "FP16",
            parameterCount: "3B",
            contextLength: 2048,
            category: .apple
        ),
        CoreMLModelCatalogEntry(
            id: "openelm-1b",
            name: "OpenELM 1.1B",
            description: "Apple's compact language model. Fast inference on any Mac.",
            repoID: "apple/OpenELM-1_1B",
            filename: "OpenELM-1_1B.mlpackage",
            sizeBytes: 700_000_000,
            quantization: "FP16",
            parameterCount: "1.1B",
            contextLength: 2048,
            category: .apple
        ),
        CoreMLModelCatalogEntry(
            id: "openelm-270m",
            name: "OpenELM 270M",
            description: "Apple's smallest model. Ultra-fast, fits anywhere.",
            repoID: "apple/OpenELM-270M",
            filename: "OpenELM-270M.mlpackage",
            sizeBytes: 270_000_000,
            quantization: "FP16",
            parameterCount: "270M",
            contextLength: 2048,
            category: .apple
        )
    ]

    // MARK: - Init

    init() {
        ensureModelDirectoryExists()
        detectSystemRAM()
        refreshDownloadStates()
    }

    // MARK: - System Detection

    private func detectSystemRAM() {
        let totalRAM = ProcessInfo.processInfo.physicalMemory
        systemRAMGB = Int(totalRAM / 1_073_741_824)
    }

    /// Returns the recommended quantization level based on available RAM.
    func recommendedQuantLevel() -> String {
        if systemRAMGB >= 32 { return "FP16" }
        if systemRAMGB >= 16 { return "Q8" }
        return "Q4"
    }

    /// Returns true if the model is too large for comfortable use on this system.
    func isModelTooLarge(_ entry: CoreMLModelCatalogEntry) -> Bool {
        return entry.recommendedRAMGB > systemRAMGB
    }

    // MARK: - Download State Management

    func refreshDownloadStates() {
        let fm = FileManager.default
        for entry in Self.catalog {
            let modelPath = modelDirectory.appendingPathComponent(entry.filename)
            if fm.fileExists(atPath: modelPath.path) {
                downloadStates[entry.id] = .downloaded
            } else if downloadStates[entry.id] == nil {
                downloadStates[entry.id] = .notDownloaded
            }
        }
    }

    func state(for entryID: String) -> CoreMLDownloadState {
        downloadStates[entryID] ?? .notDownloaded
    }

    // MARK: - Download

    func downloadModel(_ entry: CoreMLModelCatalogEntry) {
        guard state(for: entry.id) != .downloaded else { return }
        guard !state(for: entry.id).isDownloading else { return }

        guard let downloadURL = huggingFaceDownloadURL(for: entry) else {
            GRumpLogger.coreml.error("Invalid download URL for model: \(entry.name)")
            downloadStates[entry.id] = .notDownloaded
            return
        }
        let entryID = entry.id
        let totalSize = entry.sizeBytes
        let modelDir = modelDirectory
        let filename = entry.filename
        let paramCount = entry.parameterCount
        let quant = entry.quantization
        let contextLen = entry.contextLength
        let displayName = entry.name

        downloadStates[entryID] = .downloading(progress: 0, bytesReceived: 0, totalBytes: totalSize)

        let downloadTask = Task { [weak self] in
            let session = URLSession(configuration: .default)
            var request = URLRequest(url: downloadURL)
            request.timeoutInterval = 3600

            let (asyncBytes, response): (URLSession.AsyncBytes, URLResponse)
            if let data = self?.resumeData[entryID] {
                await MainActor.run { self?.resumeData.removeValue(forKey: entryID) }
                // Resume not supported with AsyncBytes — restart download
                (asyncBytes, response) = try await session.bytes(for: request)
            } else {
                (asyncBytes, response) = try await session.bytes(for: request)
            }

            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                await MainActor.run {
                    self?.downloadStates[entryID] = .error("HTTP \(http.statusCode)")
                }
                return
            }

            let expectedLength = response.expectedContentLength > 0 ? response.expectedContentLength : totalSize
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tmp")
            FileManager.default.createFile(atPath: tempURL.path, contents: nil)
            let fileHandle = try FileHandle(forWritingTo: tempURL)
            defer { try? fileHandle.close() }

            var bytesReceived: Int64 = 0
            var buffer = Data()
            let flushSize = 65_536 // 64KB flush intervals
            var lastUpdateTime = Date()

            for try await byte in asyncBytes {
                try Task.checkCancellation()
                buffer.append(byte)

                if buffer.count >= flushSize {
                    fileHandle.write(buffer)
                    bytesReceived += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)

                    let now = Date()
                    if now.timeIntervalSince(lastUpdateTime) >= 0.3 {
                        lastUpdateTime = now
                        let progress = Double(bytesReceived) / Double(expectedLength)
                        let received = bytesReceived
                        await MainActor.run {
                            self?.downloadStates[entryID] = .downloading(
                                progress: progress,
                                bytesReceived: received,
                                totalBytes: expectedLength
                            )
                        }
                    }
                }
            }

            // Flush remaining
            if !buffer.isEmpty {
                fileHandle.write(buffer)
                bytesReceived += Int64(buffer.count)
            }
            try fileHandle.close()

            let destURL = modelDir.appendingPathComponent(filename)
            let fm = FileManager.default
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.moveItem(at: tempURL, to: destURL)

            await MainActor.run {
                self?.writeManifest(
                    for: filename,
                    displayName: displayName,
                    parameterCount: paramCount,
                    quantization: quant,
                    contextLength: contextLen
                )
                self?.downloadStates[entryID] = .downloaded
                self?.activeDownloadTasks.removeValue(forKey: entryID)
            }
        }

        activeDownloadTasks[entryID] = downloadTask

        // Handle task failure
        Task { [weak self] in
            do {
                try await downloadTask.value
            } catch is CancellationError {
                // Paused or cancelled — handled elsewhere
            } catch {
                await MainActor.run {
                    self?.downloadStates[entryID] = .error(error.localizedDescription)
                    self?.activeDownloadTasks.removeValue(forKey: entryID)
                }
            }
        }
    }

    func pauseDownload(_ entryID: String) {
        activeDownloadTasks[entryID]?.cancel()
        activeDownloadTasks.removeValue(forKey: entryID)
        if case .downloading(_, let received, let total) = downloadStates[entryID] {
            downloadStates[entryID] = .paused(bytesReceived: received, totalBytes: total)
        }
    }

    func cancelDownload(_ entryID: String) {
        activeDownloadTasks[entryID]?.cancel()
        activeDownloadTasks.removeValue(forKey: entryID)
        resumeData.removeValue(forKey: entryID)
        downloadStates[entryID] = .notDownloaded
    }

    func deleteModel(_ entry: CoreMLModelCatalogEntry) {
        let modelPath = modelDirectory.appendingPathComponent(entry.filename)
        let manifestPath = modelDirectory.appendingPathComponent(
            (entry.filename as NSString).deletingPathExtension + ".manifest.json"
        )
        try? FileManager.default.removeItem(at: modelPath)
        try? FileManager.default.removeItem(at: manifestPath)
        downloadStates[entry.id] = .notDownloaded
    }

    // MARK: - HuggingFace URL

    private func huggingFaceDownloadURL(for entry: CoreMLModelCatalogEntry) -> URL? {
        // HuggingFace Hub download URL pattern
        URL(string: "https://huggingface.co/\(entry.repoID)/resolve/main/\(entry.filename)")
    }

    // MARK: - Manifest

    private func writeManifest(
        for filename: String,
        displayName: String,
        parameterCount: String,
        quantization: String,
        contextLength: Int
    ) {
        let baseName = (filename as NSString).deletingPathExtension
        let manifestPath = modelDirectory.appendingPathComponent(baseName + ".manifest.json")
        let dict: [String: Any] = [
            "displayName": displayName,
            "parameterCount": parameterCount,
            "quantization": quantization,
            "contextLength": contextLength
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) {
            try? data.write(to: manifestPath)
        }
    }

    // MARK: - Helpers

    private func ensureModelDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: modelDirectory.path) {
            try? fm.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        }
    }
}
