import Foundation
#if os(macOS)
import AppKit
#endif

/// Orchestrates ambient screen awareness: on a ~10s timer it gates on the frontmost app,
/// captures + hashes + OCRs a frame (skipping unchanged frames), redacts + classifies it,
/// stores a redacted `Observation`, and periodically writes a vault daily brief.
///
/// Opt-in (`BrainConfig.eyesEnabled`, default OFF). Raw frames never leave the capture
/// actor; only redacted text is persisted.
@MainActor
final class EyesEngine: ObservableObject {
    static let shared = EyesEngine()

    @Published private(set) var isRunning = false
    @Published private(set) var observationCount = 0

    private let capture = ScreenCaptureService()
    let store = ObservationStore()
    private let classifier = ActivityClassifier()
    private var timer: Timer?
    private var lastHash: UInt64?
    private var briefCounter = 0

    private init() {}

    /// Start the capture loop if Eyes is enabled. Idempotent.
    func start() {
        guard !isRunning else { return }
        let config = BrainConfigStore.shared.load()
        guard config.eyesEnabled else { return }

        Task { await store.open() }

        let interval = TimeInterval(max(config.eyesCaptureIntervalSeconds, 3))
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        timer = t
        isRunning = true
        GRumpLogger.capture.info("EyesEngine started (interval \(interval, privacy: .public)s)")
    }

    /// Stop the capture loop.
    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    /// Whether Screen Recording permission is granted (async probe).
    func permissionGranted() async -> Bool {
        await capture.permissionGranted()
    }

    private func tick() async {
        let config = BrainConfigStore.shared.load()
        guard config.eyesEnabled else { stop(); return }

        #if os(macOS)
        let front = NSWorkspace.shared.frontmostApplication
        let appName = front?.localizedName ?? ""
        let bundleId = front?.bundleIdentifier ?? ""
        #else
        let appName = ""
        let bundleId = ""
        #endif

        // Privacy gate: never even capture a sensitive app.
        let privacy = EyesPrivacyFilter(extraIgnoredBundleIDs: config.eyesIgnoredBundleIDs)
        if privacy.shouldIgnore(bundleId: bundleId, appName: appName) { return }

        let result = await capture.captureFrame(previousHash: lastHash)
        switch result {
        case .failed:
            return
        case .unchanged(let h):
            lastHash = h
        case .changed(let h, let text):
            lastHash = h
            let redacted = privacy.redact(text)
            guard redacted.count >= 40 else { return }   // skip near-empty frames
            let windowTitle = AmbientMonitor.shared.currentWindowTitle
            let classified = classifier.classify(appName: appName, bundleId: bundleId, text: redacted)
            let obs = Observation(
                app: appName,
                windowTitle: windowTitle,
                phash: h,
                redactedText: redacted,
                project: classified.project,
                activity: classified.activity,
                entities: classified.entities
            )
            await store.insert(obs)
            observationCount += 1

            briefCounter += 1
            if briefCounter % 6 == 0 {
                await writeBrief(app: appName, classified: classified)
            }
        }
    }

    private func writeBrief(app: String, classified: ActivityClassifier.Result) async {
        guard BrainConfigStore.shared.load().vaultEnabled else { return }
        let vault = VaultStore(workingDirectory: "")
        let entity = classified.entities.first.map { " \u{00b7} \($0)" } ?? ""
        await vault.appendDailyNote(section: "Screen", line: "\(classified.activity) in \(app)\(entity)")
    }
}
