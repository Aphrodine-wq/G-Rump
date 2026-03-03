import Foundation
import OSLog

// MARK: - Platform User (account, tier, credits)

struct PlatformUser: Equatable {
    let id: String
    let email: String
    let tier: String
    let tierName: String
    let creditsBalance: Int
    let creditsPerMonth: Int
    let creditsReplenishedAt: Int?
    let displayName: String?
    let avatarUrl: String?
}

// MARK: - Platform Service (auth + /api/me)

enum PlatformService {
    private static let tokenKeychainAccount = "PlatformAuthToken"

    /// Canonical platform API URL. Users do not configure this; the app always uses this endpoint.
    private static let defaultBaseURL = "https://api.g-rump.com"

    static var baseURL: String { defaultBaseURL }

    static var authToken: String? {
        get { KeychainStorage.get(account: tokenKeychainAccount) }
        set {
            if let v = newValue {
                KeychainStorage.set(account: tokenKeychainAccount, value: v)
            } else {
                KeychainStorage.delete(account: tokenKeychainAccount)
            }
        }
    }

    static var isLoggedIn: Bool { authToken != nil }

    // MARK: - Auth

    static func logout() {
        authToken = nil
    }

    /// Sign up with email and password. Stores JWT on success.
    static func signUp(email: String, password: String, displayName: String?) async throws -> PlatformUser {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/auth/signup") else {
            throw PlatformError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["email": email, "password": password]
        if let name = displayName, !name.isEmpty { body["displayName"] = name }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PlatformError.networkError }

        if http.statusCode == 409 {
            throw PlatformError.apiError(statusCode: 409, message: "An account with this email already exists.")
        }
        guard (200...299).contains(http.statusCode) else {
            let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let errObj = decoded?["error"] as? [String: Any]
            let msg = errObj?["message"] as? String ?? "Sign-up failed"
            throw PlatformError.apiError(statusCode: http.statusCode, message: msg)
        }

        let authResp = try JSONDecoder().decode(AuthResponse.self, from: data)
        authToken = authResp.token
        GRumpLogger.general.info("Email sign-up successful for \(email, privacy: .private)")
        return authResp.user.toPlatformUser()
    }

    /// Sign in with email and password. Stores JWT on success.
    static func signIn(email: String, password: String) async throws -> PlatformUser {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/auth/login") else {
            throw PlatformError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["email": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PlatformError.networkError }

        guard (200...299).contains(http.statusCode) else {
            let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let errObj = decoded?["error"] as? [String: Any]
            let msg = errObj?["message"] as? String ?? "Invalid email or password"
            throw PlatformError.apiError(statusCode: http.statusCode, message: msg)
        }

        let authResp = try JSONDecoder().decode(AuthResponse.self, from: data)
        authToken = authResp.token
        GRumpLogger.general.info("Email sign-in successful for \(email, privacy: .private)")
        return authResp.user.toPlatformUser()
    }

    // MARK: - Me (credits, tier)

    static func fetchMe() async throws -> PlatformUser {
        guard let token = authToken else { throw PlatformError.notLoggedIn }
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/me") else {
            throw PlatformError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PlatformError.networkError }
        if http.statusCode == 401 {
            authToken = nil
            throw PlatformError.notLoggedIn
        }
        guard http.statusCode == 200 else {
            let err = (try? JSONDecoder().decode(APIError.self, from: data))?.error ?? "Request failed"
            throw PlatformError.apiError(statusCode: http.statusCode, message: err)
        }
        let me = try JSONDecoder().decode(MeResponse.self, from: data)
        return me.toPlatformUser()
    }

    // MARK: - Profile

    static func updateProfile(displayName: String? = nil, avatarUrl: String? = nil) async throws -> PlatformUser {
        guard let token = authToken else { throw PlatformError.notLoggedIn }
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/me") else {
            throw PlatformError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var body: [String: Any?] = [:]
        if displayName != nil { body["displayName"] = displayName }
        if avatarUrl != nil { body["avatarUrl"] = avatarUrl }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PlatformError.networkError }
        if http.statusCode == 401 {
            authToken = nil
            throw PlatformError.notLoggedIn
        }
        guard http.statusCode == 200 else {
            let err = (try? JSONDecoder().decode(APIError.self, from: data))?.error ?? "Request failed"
            throw PlatformError.apiError(statusCode: http.statusCode, message: err)
        }
        let me = try JSONDecoder().decode(MeResponse.self, from: data)
        return me.toPlatformUser()
    }

    static func fetchUsage() async throws -> PlatformUsage {
        guard let token = authToken else { throw PlatformError.notLoggedIn }
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/me/usage") else {
            throw PlatformError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PlatformError.networkError }
        if http.statusCode == 401 {
            authToken = nil
            throw PlatformError.notLoggedIn
        }
        guard http.statusCode == 200 else {
            let err = (try? JSONDecoder().decode(APIError.self, from: data))?.error ?? "Request failed"
            throw PlatformError.apiError(statusCode: http.statusCode, message: err)
        }
        return try JSONDecoder().decode(PlatformUsage.self, from: data)
    }

    // MARK: - Response DTOs (fileprivate so extensions can be used in same file)

    private struct AuthResponse: Decodable {
        let token: String
        let user: AuthUser
    }

    fileprivate struct AuthUser: Decodable {
        let id: String
        let email: String
        let tier: String
        let creditsBalance: Int
        let creditsReplenishedAt: Int?
        let displayName: String?
        let avatarUrl: String?
    }

    fileprivate struct MeResponse: Decodable {
        let id: String
        let email: String
        let tier: String
        let tierName: String
        let creditsBalance: Int
        let creditsPerMonth: Int
        let creditsReplenishedAt: Int?
        let displayName: String?
        let avatarUrl: String?
    }

    struct PlatformUsage: Decodable {
        let totalCreditsUsed: Int
        let requestCount: Int
        let creditsThisMonth: Int
    }

    private struct APIError: Decodable {
        let error: String?
    }

    enum PlatformError: Error, LocalizedError {
        case invalidURL
        case networkError
        case notLoggedIn
        case apiError(statusCode: Int, message: String?)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid platform URL"
            case .networkError: return "Network error. Check your connection."
            case .notLoggedIn: return "You are not signed in."
            case .apiError(let code, let msg):
                return msg ?? "Request failed (HTTP \(code))"
            }
        }
    }
}

fileprivate extension PlatformService.AuthUser {
    func toPlatformUser() -> PlatformUser {
        let tierName = PlatformService.tierDisplayName(tier)
        return PlatformUser(id: id, email: email, tier: tier, tierName: tierName, creditsBalance: creditsBalance, creditsPerMonth: tierCreditsPerMonth(tier), creditsReplenishedAt: creditsReplenishedAt, displayName: displayName, avatarUrl: avatarUrl)
    }
}

fileprivate extension PlatformService.MeResponse {
    func toPlatformUser() -> PlatformUser {
        PlatformUser(id: id, email: email, tier: tier, tierName: tierName, creditsBalance: creditsBalance, creditsPerMonth: creditsPerMonth, creditsReplenishedAt: creditsReplenishedAt, displayName: displayName, avatarUrl: avatarUrl)
    }
}

private func tierCreditsPerMonth(_ tier: String) -> Int {
    switch tier {
    case "starter": return 2000
    case "pro": return 5000
    case "team": return 25000
    default: return 500
    }
}

extension PlatformService {
    static func tierDisplayName(_ tier: String) -> String {
        switch tier {
        case "starter": return "Starter"
        case "pro": return "Pro"
        case "team": return "Team"
        default: return "Free"
        }
    }
}
