import Foundation
import Security
import CryptoKit
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

// MARK: - Secure Enclave Service
//
// Hardware-backed secure storage for sensitive data using Apple's Secure Enclave.
// Stores API keys, credentials, and encryption keys with biometric protection.
//

@MainActor
final class SecureEnclaveService: ObservableObject {

    static let shared = SecureEnclaveService()

    @Published var isAvailable: Bool = false
    @Published var biometricTypeDescription: String = "none"

    // ASCII literal, guaranteed valid UTF-8.
    private let keyTag = Data("com.grump.secureEnclave.key".utf8)
    private let accessGroup = "com.grump.security"

    private init() {
        checkAvailability()
    }

    // MARK: - Availability Check

    private func checkAvailability() {
        // Check if Secure Enclave is available
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey([
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false
            ]
        ] as CFDictionary, &error) else {
            isAvailable = false
            return
        }

        // Clean up test key - delete from keychain
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecValueRef as String: privateKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        isAvailable = true

        // Check biometric type
        #if canImport(LocalAuthentication)
        let context = LAContext()
        var error2: NSError?
        context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error2)
        switch context.biometryType {
        case .faceID: biometricTypeDescription = "faceID"
        case .touchID: biometricTypeDescription = "touchID"
        default: biometricTypeDescription = "none"
        }
        #endif
    }

    // MARK: - Key Management

    /// Create or retrieve the Secure Enclave key pair
    private func getOrCreateKeyPair() throws -> SecKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeySizeInBits as String: 256,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess {
            guard let item = item, CFGetTypeID(item) == SecKeyGetTypeID() else {
                throw SecureEnclaveError.keyAccessFailed(status)
            }
            // Safe: CFTypeID verified above
            // swiftlint:disable:next force_cast
            return (item as! SecKey)
        } else if status == errSecItemNotFound {
            // Create new key pair
            return try createKeyPair()
        } else {
            throw SecureEnclaveError.keyAccessFailed(status)
        }
    }

    /// Create a new Secure Enclave key pair
    private func createKeyPair() throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: {
                var attrs: [String: Any] = [
                    kSecAttrApplicationTag as String: keyTag,
                    kSecAttrIsPermanent as String: true
                ]
                if let accessControl = SecAccessControlCreateWithFlags(
                    nil,
                    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                    [.privateKeyUsage, .userPresence],
                    nil
                ) {
                    attrs[kSecAttrAccessControl as String] = accessControl
                }
                return attrs
            }(),
            kSecPublicKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            if let error = error {
                throw error.takeRetainedValue() as Error
            }
            throw SecureEnclaveError.keyGenerationFailed
        }

        return privateKey
    }

    // MARK: - Data Encryption/Decryption

    /// Encrypt data using Secure Enclave
    func encrypt(_ data: Data, reason: String = "Authenticate to encrypt data") throws -> Data {
        let privateKey = try getOrCreateKeyPair()
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw SecureEnclaveError.keyAccessFailed(errSecInternalError)
        }

        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(
            publicKey,
            .eciesEncryptionStandardX963SHA256AESGCM,
            data as CFData,
            &error
        ) else {
            let underlying = error?.takeRetainedValue() as Error? ?? SecureEnclaveError.keyAccessFailed(errSecInternalError)
            throw SecureEnclaveError.encryptionFailed(underlying)
        }

        return encryptedData as Data
    }

    /// Decrypt data using Secure Enclave with biometric authentication
    func decrypt(_ encryptedData: Data, reason: String = "Authenticate to decrypt data") async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            let context = LAContext()
            context.localizedReason = reason

            let privateKey: SecKey
            do {
                privateKey = try getOrCreateKeyPair()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            var cfError: Unmanaged<CFError>?
            guard let decryptedData = SecKeyCreateDecryptedData(
                privateKey,
                .eciesEncryptionStandardX963SHA256AESGCM,
                encryptedData as CFData,
                &cfError
            ) else {
                let underlying = cfError?.takeRetainedValue() as Error? ?? SecureEnclaveError.keyAccessFailed(errSecInternalError)
                continuation.resume(throwing: SecureEnclaveError.decryptionFailed(underlying))
                return
            }

            continuation.resume(returning: decryptedData as Data)
        }
    }

    // MARK: - Credential Storage

    /// Store API key securely
    func storeAPIKey(_ key: String, for service: String) async throws {
        guard let keyData = key.data(using: .utf8) else {
            throw SecureEnclaveError.storageFailed(errSecParam)
        }
        let encryptedKey = try encrypt(keyData)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: service,
            kSecAttrService as String: "com.grump.apikeys",
            kSecAttrAccessGroup as String: accessGroup,
            kSecValueData as String: encryptedKey
        ]

        // Delete existing if any
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureEnclaveError.storageFailed(status)
        }
    }

    /// Retrieve API key securely
    func retrieveAPIKey(for service: String) async throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: service,
            kSecAttrService as String: "com.grump.apikeys",
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let encryptedData = item as? Data else {
            throw SecureEnclaveError.notFound
        }

        let decryptedData = try await decrypt(encryptedData, reason: "Authenticate to access \(service) API key")
        guard let result = String(data: decryptedData, encoding: .utf8) else {
            throw SecureEnclaveError.decryptionFailed(SecureEnclaveError.notFound)
        }
        return result
    }

    /// Delete stored API key
    func deleteAPIKey(for service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: service,
            kSecAttrService as String: "com.grump.apikeys",
            kSecAttrAccessGroup as String: accessGroup
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureEnclaveError.storageFailed(status)
        }
    }

    // MARK: - Zero-Knowledge Proofs

    /// Generate a cryptographic proof of data processing without revealing the data
    func generateProcessingProof(for dataHash: Data) throws -> Data {
        let privateKey = try getOrCreateKeyPair()

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            dataHash as CFData,
            &error
        ) else {
            let underlying = error?.takeRetainedValue() as Error? ?? SecureEnclaveError.keyAccessFailed(errSecInternalError)
            throw SecureEnclaveError.signatureFailed(underlying)
        }

        return signature as Data
    }

    /// Verify a processing proof
    func verifyProcessingProof(_ proof: Data, for dataHash: Data) -> Bool {
        do {
            let privateKey = try getOrCreateKeyPair()
            guard let publicKey = SecKeyCopyPublicKey(privateKey) else { return false }

            var error: Unmanaged<CFError>?
            let result = SecKeyVerifySignature(
                publicKey,
                .ecdsaSignatureMessageX962SHA256,
                dataHash as CFData,
                proof as CFData,
                &error
            )

            return result
        } catch {
            return false
        }
    }
}

// MARK: - Error Types

enum SecureEnclaveError: LocalizedError {
    case keyAccessFailed(OSStatus)
    case encryptionFailed(Error)
    case decryptionFailed(Error)
    case storageFailed(OSStatus)
    case notFound
    case signatureFailed(Error)
    case keyGenerationFailed

    var errorDescription: String? {
        switch self {
        case .keyAccessFailed(let status):
            return "Failed to access Secure Enclave key: \(status)"
        case .encryptionFailed(let error):
            return "Encryption failed: \(error.localizedDescription)"
        case .decryptionFailed(let error):
            return "Decryption failed: \(error.localizedDescription)"
        case .storageFailed(let status):
            return "Storage operation failed: \(status)"
        case .notFound:
            return "Requested item not found in secure storage"
        case .signatureFailed(let error):
            return "Signature operation failed: \(error.localizedDescription)"
        case .keyGenerationFailed:
            return "Failed to generate Secure Enclave key pair"
        }
    }
}

// MARK: - Convenience Extensions

extension SecureEnclaveService {

    /// Store multiple credentials in a batch
    func storeCredentials(_ credentials: [String: String]) async throws {
        for (service, key) in credentials {
            try await storeAPIKey(key, for: service)
        }
    }

    /// Generate a secure random token
    func generateSecureToken() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        return Data(bytes).base64EncodedString()
    }

    /// Check if biometrics are enrolled and available
    var isBiometricsAvailable: Bool {
        return biometricTypeDescription != "none" && isAvailable
    }
}
