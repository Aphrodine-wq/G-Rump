import Foundation
import AVFoundation

/// Text-to-speech output for assistant replies. Uses the native, offline
/// `AVSpeechSynthesizer` by default, and ElevenLabs when the user has enabled it
/// and stored an API key — failing soft back to native on any error.
///
/// Gricean/Conscience gating of speech is intentionally deferred to Phase 4; this
/// service just sanitizes markdown and speaks.
@MainActor
final class SpeechOutputService: NSObject, ObservableObject {
    static let shared = SpeechOutputService()

    @Published private(set) var isSpeaking = false

    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?

    override init() {
        super.init()
        synth.delegate = self
    }

    /// Speak the given text if TTS is enabled. Interrupts any current utterance.
    func speak(_ text: String) {
        let config = BrainConfigStore.shared.load()
        guard config.ttsEnabled else { return }
        var clean = Self.sanitize(text)
        // Conscience: never voice secrets that slipped into a reply.
        if config.conscienceEnabled {
            clean = EyesPrivacyFilter().redact(clean)
        }
        guard !clean.isEmpty else { return }
        stop()

        if config.useElevenLabs,
           let key = KeychainStorage.get(account: config.elevenLabsKeychainKey),
           !key.isEmpty {
            isSpeaking = true
            Task { [weak self] in
                do {
                    let data = try await ElevenLabsTTSProvider.synthesize(
                        text: clean,
                        apiKey: key,
                        voiceId: config.elevenLabsVoiceId,
                        modelId: config.elevenLabsModelId
                    )
                    self?.playAudio(data)
                } catch {
                    GRumpLogger.brain.error("ElevenLabs TTS failed, using native voice: \(error.localizedDescription, privacy: .public)")
                    self?.speakNative(clean, config: config)
                }
            }
            return
        }

        speakNative(clean, config: config)
    }

    /// Stop any in-progress speech (native or ElevenLabs playback).
    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        player?.stop()
        player = nil
        isSpeaking = false
    }

    /// Convenience for the UI: toggle speaking of `text`.
    func toggle(_ text: String) {
        if isSpeaking { stop() } else { speak(text) }
    }

    // MARK: - Private

    private func speakNative(_ text: String, config: BrainConfig) {
        let utterance = AVSpeechUtterance(string: text)
        if !config.voiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: config.voiceIdentifier) {
            utterance.voice = voice
        }
        isSpeaking = true
        synth.speak(utterance)
    }

    private func playAudio(_ data: Data) {
        do {
            let p = try AVAudioPlayer(data: data)
            p.delegate = self
            player = p
            isSpeaking = true
            p.play()
        } catch {
            GRumpLogger.brain.error("TTS audio playback failed: \(error.localizedDescription, privacy: .public)")
            isSpeaking = false
        }
    }

    /// Strip markdown so the synthesizer reads prose, not syntax. Caps length.
    static func sanitize(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "(?s)```.*?```", with: " (code block) ", options: .regularExpression)
        s = s.replacingOccurrences(of: "[`*_#>|]", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(s.prefix(4000))
    }
}

// MARK: - Delegates

extension SpeechOutputService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

extension SpeechOutputService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
