// ╔══════════════════════════════════════════════════════════════╗
// ║  AIKeyValidator.swift                                        ║
// ║  Cheap authed probe to verify a provider API key             ║
// ╚══════════════════════════════════════════════════════════════╝

import Foundation

// MARK: - Result

/// Outcome of a key probe. `.indeterminate` means the network — not the key —
/// failed, so callers keep the saved key and surface the reason as a warning.
enum KeyValidationResult: Equatable, Sendable {
    case valid
    case invalid
    case indeterminate(String)
}

/// View-facing probe lifecycle shared by Settings and onboarding.
enum KeyValidationState: Equatable, Sendable {
    case idle
    case validating
    case result(KeyValidationResult)
}

// MARK: - Validator

enum AIKeyValidator {

    /// Validation is a UX nicety — never worth a long stall.
    static let timeout: TimeInterval = 10

    /// Probes the provider with the cheapest authenticated GET available and
    /// classifies the answer. Never throws: network trouble is a result, not
    /// an error, because the caller has already persisted the key.
    static func validate(provider: AIProvider, apiKey: String, baseURL: String? = nil) async -> KeyValidationResult {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid }
        guard let request = validationRequest(for: provider, apiKey: trimmed, baseURL: baseURL) else {
            return .indeterminate("The base URL for \(provider.displayName) is not a valid URL")
        }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .indeterminate("Unexpected response from \(provider.displayName)")
            }
            return classify(statusCode: http.statusCode, provider: provider)
        } catch {
            GRumpLogger.ai.error("Key probe for \(provider.rawValue) failed: \(error.localizedDescription)")
            return .indeterminate(reason(for: error))
        }
    }

    // MARK: - Pure pieces (unit-tested)

    /// GET /models for the native providers; OpenRouter documents GET /key as
    /// the canonical "is this key alive" endpoint. Keys travel in headers
    /// only — never in the URL, where they would leak into logs.
    static func validationRequest(for provider: AIProvider, apiKey: String, baseURL: String? = nil) -> URLRequest? {
        let base = baseURL ?? provider.defaultBaseURL
        let path = provider == .openRouter ? "/key" : "/models"
        guard let url = URL(string: base + path), url.scheme != nil else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        switch provider {
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openAI, .openRouter:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .google:
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        }
        return request
    }

    static func classify(statusCode: Int, provider: AIProvider) -> KeyValidationResult {
        switch statusCode {
        case 200...299:
            return .valid
        case 401, 403:
            return .invalid
        default:
            return .indeterminate("\(provider.displayName) answered HTTP \(statusCode)")
        }
    }

    static func reason(for error: Error) -> String {
        switch (error as? URLError)?.code {
        case .timedOut:
            return "The request timed out"
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
            return "No connection to the provider"
        default:
            return error.localizedDescription
        }
    }
}
