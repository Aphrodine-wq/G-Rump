import Foundation

/// What kind of sensitive surface is currently on screen, inferred from OCR text.
enum Surface: String, Sendable {
    case payment
    case auth
    case secrets
    case neutral
}

/// Classifies live screen OCR text into a sensitive surface using high-precision
/// MULTI-WORD tells (single words like "token" or "checkout" false-trip too easily).
struct SurfaceClassifier {

    private static let secretsSignals = [
        "api key", "secret key", "seed phrase", "access token", "private key",
        "recovery phrase", "client secret", "secret access key"
    ]
    private static let paymentSignals = [
        "card number", "cvv", "cvc", "expiration date", "billing address",
        "security code", "card holder", "credit card", "debit card"
    ]
    private static let authSignals = [
        "sign in", "log in", "two-factor", "enter your password", "verification code",
        "one-time code", "authenticator", "2fa code", "confirm your password"
    ]

    /// Classify text. Priority: secrets > payment > auth > neutral.
    func classify(_ text: String) -> Surface {
        let lower = text.lowercased()
        if Self.secretsSignals.contains(where: { lower.contains($0) }) { return .secrets }
        if Self.paymentSignals.contains(where: { lower.contains($0) }) { return .payment }
        if Self.authSignals.contains(where: { lower.contains($0) }) { return .auth }
        return .neutral
    }

    /// The matched evidence phrases (for the verdict reason).
    func evidence(in text: String, for surface: Surface) -> [String] {
        let lower = text.lowercased()
        let signals: [String]
        switch surface {
        case .secrets: signals = Self.secretsSignals
        case .payment: signals = Self.paymentSignals
        case .auth: signals = Self.authSignals
        case .neutral: return []
        }
        return signals.filter { lower.contains($0) }
    }
}
