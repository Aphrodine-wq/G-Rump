import Foundation
import Combine

/// Generic, user-owned configuration for the Brain subsystem (vault, voice, and the
/// autonomy/perception feature flags introduced across later phases).
///
/// Persisted as human-readable JSON at `~/.grump/brain.json`. Nothing here is
/// personal or hard-coded — every field ships with a safe, generic default, and
/// anything that touches the screen or takes autonomous action defaults OFF.
struct BrainConfig: Codable, Equatable {

    // MARK: - Feature Flags

    /// Markdown vault projection + write-back (Phase 2).
    var vaultEnabled: Bool = true
    /// Ambient screen awareness (Phase 3). Off by default — requires Screen Recording.
    var eyesEnabled: Bool = false
    /// Extra bundle IDs (beyond the built-in sensitive defaults) Eyes must never capture.
    var eyesIgnoredBundleIDs: [String] = []
    /// Seconds between Eyes capture ticks.
    var eyesCaptureIntervalSeconds: Int = 10
    /// Conscience gate before tool execution / autonomous actions (Phase 4).
    var conscienceEnabled: Bool = true
    /// Autonomous background daemon (Phase 5). Off by default.
    var daemonEnabled: Bool = false
    /// Text-to-speech output (Phase 1).
    var ttsEnabled: Bool = false
    /// Learning loop: outcome reflection, lesson injection, skill proposals.
    var learningEnabled: Bool = true
    /// Post lesson add/weaken notices to the conversation (transparency).
    var learningNoticesEnabled: Bool = true
    /// Reflection cadence: also reflect every N runs even without failures.
    var reflectionEveryNRuns: Int = 5
    /// How many lessons ride along in the system prompt.
    var lessonInjectionCount: Int = 5

    // MARK: - Personality / Voice

    /// Optional display name for the agent. Empty = derive from SOUL.md.
    var displayName: String = ""
    /// `AVSpeechSynthesisVoice` identifier for native TTS. Empty = system default.
    var voiceIdentifier: String = ""
    /// Prefer ElevenLabs TTS when a key is available.
    var useElevenLabs: Bool = false
    /// Name of the Keychain entry holding the ElevenLabs API key.
    /// We store only the *reference*, never the secret itself.
    var elevenLabsKeychainKey: String = "elevenlabs-api-key"
    /// ElevenLabs voice id (defaults to a public stock voice). User-overridable.
    var elevenLabsVoiceId: String = "21m00Tcm4TlvDq8ikWAM"
    /// ElevenLabs model id for synthesis.
    var elevenLabsModelId: String = "eleven_turbo_v2_5"

    static let `default` = BrainConfig()

    init() {}

    // Tolerant decode: fields added in later versions fall back to their
    // defaults instead of failing the whole file (which would silently reset
    // every flag to factory settings).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = BrainConfig()
        vaultEnabled = try container.decodeIfPresent(Bool.self, forKey: .vaultEnabled) ?? defaults.vaultEnabled
        eyesEnabled = try container.decodeIfPresent(Bool.self, forKey: .eyesEnabled) ?? defaults.eyesEnabled
        eyesIgnoredBundleIDs = try container.decodeIfPresent([String].self, forKey: .eyesIgnoredBundleIDs) ?? defaults.eyesIgnoredBundleIDs
        eyesCaptureIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .eyesCaptureIntervalSeconds) ?? defaults.eyesCaptureIntervalSeconds
        conscienceEnabled = try container.decodeIfPresent(Bool.self, forKey: .conscienceEnabled) ?? defaults.conscienceEnabled
        daemonEnabled = try container.decodeIfPresent(Bool.self, forKey: .daemonEnabled) ?? defaults.daemonEnabled
        ttsEnabled = try container.decodeIfPresent(Bool.self, forKey: .ttsEnabled) ?? defaults.ttsEnabled
        learningEnabled = try container.decodeIfPresent(Bool.self, forKey: .learningEnabled) ?? defaults.learningEnabled
        learningNoticesEnabled = try container.decodeIfPresent(Bool.self, forKey: .learningNoticesEnabled) ?? defaults.learningNoticesEnabled
        reflectionEveryNRuns = try container.decodeIfPresent(Int.self, forKey: .reflectionEveryNRuns) ?? defaults.reflectionEveryNRuns
        lessonInjectionCount = try container.decodeIfPresent(Int.self, forKey: .lessonInjectionCount) ?? defaults.lessonInjectionCount
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? defaults.displayName
        voiceIdentifier = try container.decodeIfPresent(String.self, forKey: .voiceIdentifier) ?? defaults.voiceIdentifier
        useElevenLabs = try container.decodeIfPresent(Bool.self, forKey: .useElevenLabs) ?? defaults.useElevenLabs
        elevenLabsKeychainKey = try container.decodeIfPresent(String.self, forKey: .elevenLabsKeychainKey) ?? defaults.elevenLabsKeychainKey
        elevenLabsVoiceId = try container.decodeIfPresent(String.self, forKey: .elevenLabsVoiceId) ?? defaults.elevenLabsVoiceId
        elevenLabsModelId = try container.decodeIfPresent(String.self, forKey: .elevenLabsModelId) ?? defaults.elevenLabsModelId
    }
}

// MARK: - BrainConfigStore (synchronous, lock-guarded source of truth)

/// Thread-safe accessor for the persisted `BrainConfig`. Reads are served from an
/// in-memory cache so feature-flag checks on the conversation path stay cheap.
final class BrainConfigStore: @unchecked Sendable {

    static let shared = BrainConfigStore()

    private let lock = NSLock()
    private var cached: BrainConfig

    private static var configPath: URL {
        BrainPaths.grumpHome.appendingPathComponent("brain.json")
    }

    private init() {
        cached = BrainConfigStore.loadFromDisk() ?? .default
    }

    /// Current configuration (cached).
    func load() -> BrainConfig {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    /// Persist a new configuration to disk and refresh the cache.
    @discardableResult
    func save(_ config: BrainConfig) -> Bool {
        lock.lock()
        cached = config
        lock.unlock()

        let dir = BrainConfigStore.configPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: BrainConfigStore.configPath, options: .atomic)
            return true
        } catch {
            GRumpLogger.brain.error("Failed to save brain.json: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Write defaults to disk if no config file exists yet.
    func seedIfNeeded() {
        guard !FileManager.default.fileExists(atPath: BrainConfigStore.configPath.path) else { return }
        save(cached)
    }

    private static func loadFromDisk() -> BrainConfig? {
        guard let data = try? Data(contentsOf: configPath) else { return nil }
        return try? JSONDecoder().decode(BrainConfig.self, from: data)
    }
}

// MARK: - BrainConfigModel (SwiftUI binding)

/// Observable wrapper for Settings UI. Mutations persist immediately.
@MainActor
final class BrainConfigModel: ObservableObject {
    @Published var config: BrainConfig {
        didSet {
            guard config != oldValue else { return }
            BrainConfigStore.shared.save(config)
        }
    }

    init() {
        config = BrainConfigStore.shared.load()
    }

    /// Reload from the store (e.g. if changed elsewhere).
    func reload() {
        config = BrainConfigStore.shared.load()
    }
}
