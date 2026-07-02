import Foundation

/// Privacy guard for Eyes: decides which apps must never be captured, and redacts
/// secrets out of OCR text BEFORE it is ever persisted. Defaults are generic and
/// user-extendable via `BrainConfig.eyesIgnoredBundleIDs`.
struct EyesPrivacyFilter {

    /// Bundle IDs / app-name fragments that are never captured (password managers,
    /// keychain, banking, private auth surfaces). Generic, no personal entries.
    static let defaultIgnoredBundleIDs: [String] = [
        "com.1password", "com.agilebits", "com.bitwarden", "com.lastpass",
        "com.apple.keychainaccess", "com.dashlane", "com.callpod.keeper",
        "com.googlecode.iterm2.private", "org.keepassxc"
    ]

    /// App-name fragments (lowercased) treated as sensitive regardless of bundle id.
    static let sensitiveNameFragments: [String] = [
        "1password", "bitwarden", "lastpass", "keychain", "dashlane", "keeper",
        "banking", "wallet", "authenticator"
    ]

    private let extraIgnored: [String]

    init(extraIgnoredBundleIDs: [String] = []) {
        self.extraIgnored = extraIgnoredBundleIDs.map { $0.lowercased() }
    }

    /// Whether the frontmost app should be skipped entirely (never captured).
    func shouldIgnore(bundleId: String, appName: String) -> Bool {
        let bid = bundleId.lowercased()
        let name = appName.lowercased()
        if Self.defaultIgnoredBundleIDs.contains(where: { bid.contains($0) }) { return true }
        if extraIgnored.contains(where: { !$0.isEmpty && bid.contains($0) }) { return true }
        if Self.sensitiveNameFragments.contains(where: { name.contains($0) }) { return true }
        return false
    }

    /// Redact secrets from OCR text before persistence. Conservative — over-redacts
    /// rather than risk storing a credential.
    func redact(_ text: String) -> String {
        var s = text
        for (pattern, replacement) in Self.redactionRules {
            s = s.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return s
    }

    /// (regex, replacement) pairs applied in order.
    private static let redactionRules: [(String, String)] = [
        // OpenAI / generic provider keys
        ("sk-[A-Za-z0-9_-]{16,}", "[REDACTED_KEY]"),
        // AWS access key ids
        ("AKIA[0-9A-Z]{16}", "[REDACTED_AWS_KEY]"),
        // Bearer tokens
        ("(?i)bearer\\s+[A-Za-z0-9._-]{12,}", "Bearer [REDACTED_TOKEN]"),
        // GitHub tokens
        ("gh[pousr]_[A-Za-z0-9]{20,}", "[REDACTED_GH_TOKEN]"),
        // Long hex/base64-ish secrets (40+)
        ("\\b[A-Fa-f0-9]{40,}\\b", "[REDACTED_HASH]"),
        // Credit-card-like number groups
        ("\\b(?:\\d[ -]*?){13,16}\\b", "[REDACTED_CARD]"),
        // Private key blocks (header line)
        ("-----BEGIN [A-Z ]*PRIVATE KEY-----", "[REDACTED_PRIVATE_KEY]"),
        // Email addresses
        ("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", "[REDACTED_EMAIL]")
    ]
}
