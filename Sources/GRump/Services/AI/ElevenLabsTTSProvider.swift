import Foundation

/// Optional ElevenLabs text-to-speech provider. Used only when an API key is present
/// in the Keychain; every failure path falls back to the native synthesizer upstream.
///
/// Generic and product-safe: the key is supplied by the user and read from the Keychain
/// by reference — it never lives in `brain.json` or source.
enum ElevenLabsTTSProvider {

    enum TTSError: Error {
        case missingKey
        case badResponse(Int)
        case emptyAudio
    }

    /// Synthesize `text` to MP3 audio data via the ElevenLabs streaming endpoint.
    static func synthesize(
        text: String,
        apiKey: String,
        voiceId: String,
        modelId: String
    ) async throws -> Data {
        guard !apiKey.isEmpty else { throw TTSError.missingKey }

        let urlString = "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)"
        guard let url = URL(string: urlString) else { throw TTSError.badResponse(-1) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text": text,
            "model_id": modelId,
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TTSError.badResponse(http.statusCode)
        }
        guard !data.isEmpty else { throw TTSError.emptyAudio }
        return data
    }
}
