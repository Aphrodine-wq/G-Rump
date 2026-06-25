import Foundation
import SwiftUI

// MARK: - Privacy Manifest Generator
//
// Automatically generates App Store privacy manifests from code analysis.
// Demonstrates G-Rump's commitment to privacy and helps developers comply
// with App Store requirements.
//

@MainActor
final class PrivacyManifestGenerator: ObservableObject {

    static let shared = PrivacyManifestGenerator()

    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0
    @Published var generatedManifest: PrivacyManifest?
    @Published var analysisResults: [PrivacyAnalysisResult] = []

    private let fileManager = FileManager.default

    // MARK: - Main Analysis

    func analyzeProject(at url: URL) async throws {
        isAnalyzing = true
        analysisProgress = 0
        analysisResults.removeAll()

        // Phase 1: Scan for data collection patterns
        let dataCollectionResults = try await scanForDataCollection(url: url)
        analysisProgress = 0.3

        // Phase 2: Analyze tracking and analytics
        let trackingResults = try await scanForTracking(url: url)
        analysisProgress = 0.6

        // Phase 3: Check third-party SDKs
        let sdkResults = try await analyzeThirdPartySDKs(url: url)
        analysisProgress = 0.9

        // Phase 4: Generate manifest
        let manifest = try generateManifest(
            dataCollection: dataCollectionResults,
            tracking: trackingResults,
            sdks: sdkResults
        )

        generatedManifest = manifest
        analysisResults = dataCollectionResults + trackingResults + sdkResults
        analysisProgress = 1.0
        isAnalyzing = false
    }

    // MARK: - Data Collection Analysis

    private func scanForDataCollection(url: URL) async throws -> [PrivacyAnalysisResult] {
        var results: [PrivacyAnalysisResult] = []

        // Define sensitive data patterns
        let patterns: [DataCategory: [String]] = [
            .contactInfo: [
                "CNContactStore", "ABAddressBookRef", "Contacts.framework",
                "email", "phone", "address", "fullName"
            ],
            .health: [
                "HealthKit", "HKHealthStore", "clinicalHealthRecords",
                "workout", "heartRate", "stepCount", "sleepAnalysis"
            ],
            .financial: [
                "PassKit", "PKPaymentAuthorizationController", "SKPaymentQueue",
                "creditCard", "bankAccount", "transaction"
            ],
            .location: [
                "CLLocationManager", "CoreLocation", "latitude", "longitude",
                "significantLocationChanges", "geofence"
            ],
            .sensitive: [
                "photoLibrary", "camera", "microphone", "faceID",
                "touchID", "biometric", "reminder", "calendar"
            ],
            .contacts: [
                "social", "friends", "followers", "profile", "userID"
            ],
            .userContent: [
                "userGenerated", "photos", "videos", "audio", "files",
                "documents", "messages", "comments"
            ],
            .browsing: [
                "SafariServices", "SFSafariViewController", "webkit",
                "cookies", "browsingHistory", "searchHistory"
            ],
            .searchHistory: [
                "searchQuery", "searchTerm", "autocomplete", "searchHistory"
            ],
            .productInteraction: [
                "purchase", "view", "click", "addToCart", "wishlist",
                "productView", "categoryView"
            ],
            .advertisingData: [
                "IDFA", "advertisingIdentifier", "deviceIdentifier",
                "personalizedAds", "targetedAds"
            ],
            .other: [
                "analytics", "crashlytics", "metrics", "performance",
                "diagnostics", "feedback"
            ]
        ]

        // Scan Swift files
        let swiftFiles = try findSwiftFiles(in: url)

        for (index, file) in swiftFiles.enumerated() {
            let content = try String(contentsOf: file)

            for (category, keywords) in patterns {
                for keyword in keywords {
                    if content.localizedCaseInsensitiveContains(keyword) {
                        results.append(PrivacyAnalysisResult(
                            type: .dataCollection,
                            category: category,
                            file: file.lastPathComponent,
                            line: findLineNumber(of: keyword, in: content),
                            description: "Potential data collection: \(keyword)",
                            severity: determineSeverity(for: keyword, in: category)
                        ))
                    }
                }
            }

            // Update progress
            await MainActor.run {
                analysisProgress = 0.3 + (Double(index) / Double(swiftFiles.count)) * 0.1
            }
        }

        return results
    }

    // MARK: - Tracking Analysis

    private func scanForTracking(url: URL) async throws -> [PrivacyAnalysisResult] {
        var results: [PrivacyAnalysisResult] = []

        let trackingPatterns: [TrackingType: [String]] = [
            .analytics: [
                "FirebaseAnalytics", "Amplitude", "Mixpanel", "Segment",
                "analytics", "trackEvent", "logEvent", "userProperties"
            ],
            .advertising: [
                "GoogleMobileAds", "AdMob", "FacebookAds", "AppLovin",
                "bannerAd", "interstitialAd", "rewardedAd"
            ],
            .crashReporting: [
                "Crashlytics", "Bugsnag", "Sentry", "FirebaseCrashlytics",
                "crash", "exception", "errorReporting"
            ],
            .performanceMonitoring: [
                "FirebasePerformance", "NewRelic", "Dynatrace",
                "performanceTrace", "networkMonitor"
            ],
            .attribution: [
                "AppsFlyer", "Adjust", "Branch", "Kochava",
                "attribution", "deepLink", "installReferrer"
            ]
        ]

        let swiftFiles = try findSwiftFiles(in: url)

        for file in swiftFiles {
            let content = try String(contentsOf: file)

            for (type, keywords) in trackingPatterns {
                for keyword in keywords {
                    if content.localizedCaseInsensitiveContains(keyword) {
                        results.append(PrivacyAnalysisResult(
                            type: .tracking,
                            category: DataCategory.other,
                            file: file.lastPathComponent,
                            line: findLineNumber(of: keyword, in: content),
                            description: "Tracking implementation: \(keyword)",
                            severity: .medium
                        ))
                    }
                }
            }
        }

        return results
    }

    // MARK: - Third-Party SDK Analysis

    private func analyzeThirdPartySDKs(url: URL) async throws -> [PrivacyAnalysisResult] {
        var results: [PrivacyAnalysisResult] = []

        // Check Package.swift for dependencies
        let packageFile = url.appendingPathComponent("Package.swift")
        if fileManager.fileExists(atPath: packageFile.path) {
            let content = try String(contentsOf: packageFile)

            // Known SDKs and their privacy implications
            let sdkPrivacyMap: [String: SDKPrivacyInfo] = [
                "Firebase": .init(collects: [.analytics, .crashReporting], purpose: "Analytics and crash reporting"),
                "Google": .init(collects: [.advertisingData, .analytics], purpose: "Advertising and analytics"),
                "Facebook": .init(collects: [.advertisingData, .contacts, .userContent], purpose: "Social features and advertising"),
                "Amplitude": .init(collects: [.analytics, .userContent], purpose: "Product analytics"),
                "Segment": .init(collects: [.analytics, .userContent], purpose: "Data collection and routing"),
                "AppsFlyer": .init(collects: [.advertisingData, .analytics], purpose: "Mobile attribution"),
                "Adjust": .init(collects: [.advertisingData, .analytics], purpose: "Mobile attribution"),
                "Branch": .init(collects: [.advertisingData, .analytics], purpose: "Deep linking and attribution"),
                "Mixpanel": .init(collects: [.analytics, .userContent], purpose: "Product analytics"),
                "Sentry": .init(collects: [.crashReporting], purpose: "Error monitoring"),
                "Bugsnag": .init(collects: [.crashReporting], purpose: "Error monitoring"),
                "NewRelic": .init(collects: [.performanceMonitoring, .analytics], purpose: "Performance monitoring"),
                "Dynatrace": .init(collects: [.performanceMonitoring], purpose: "Performance monitoring")
            ]

            for (sdk, info) in sdkPrivacyMap {
                if content.contains(sdk) {
                    results.append(PrivacyAnalysisResult(
                        type: .thirdPartySDK,
                        category: .other,
                        file: "Package.swift",
                        line: 0,
                        description: "Third-party SDK: \(sdk) - \(info.purpose)",
                        severity: .high
                    ))

                    // Add specific data collection for this SDK
                    for category in info.collects {
                        results.append(PrivacyAnalysisResult(
                            type: .dataCollection,
                            category: category,
                            file: "Package.swift",
                            line: 0,
                            description: "Data collected by \(sdk): \(category.rawValue)",
                            severity: .medium
                        ))
                    }
                }
            }
        }

        return results
    }

    // MARK: - Manifest Generation

    private func generateManifest(
        dataCollection: [PrivacyAnalysisResult],
        tracking: [PrivacyAnalysisResult],
        sdks: [PrivacyAnalysisResult]
    ) throws -> PrivacyManifest {

        // Determine which data categories are collected
        var collectedCategories: Set<DataCategory> = []
        var usedPurposes: Set<DataPurpose> = []

        for result in dataCollection {
            if result.type == .dataCollection {
                collectedCategories.insert(result.category)

                // Infer purposes based on context
                if result.description.contains("analytics") {
                    usedPurposes.insert(.analytics)
                } else if result.description.contains("ad") {
                    usedPurposes.insert(.advertising)
                } else if result.description.contains("function") {
                    usedPurposes.insert(.appFunctionality)
                }
            }
        }

        // Always include app functionality
        usedPurposes.insert(.appFunctionality)

        // Check for tracking
        let hasTracking = !tracking.isEmpty

        return PrivacyManifest(
            version: "1.0.0",
            dataCollected: Array(collectedCategories).map { category in
                DataCollectedEntry(
                    dataCategory: category,
                    purposes: Array(usedPurposes),
                    isLinked: false,
                    isTracking: hasTracking && shouldTrack(for: category),
                    isEphemeral: isEphemeral(for: category)
                )
            },
            tracking: hasTracking ? [
                TrackingEntry(
                    trackingDomain: "self",
                    isTrackingEnabled: true
                )
            ] : [],
            thirdPartySDKs: sdks.compactMap { result in
                if result.type == .thirdPartySDK,
                   let sdkName = extractSDKName(from: result.description) {
                    return ThirdPartySDKEntry(
                        name: sdkName,
                        privacyPolicyURL: nil, // Would need to be looked up
                        purposes: [.analytics]
                    )
                }
                return nil
            }
        )
    }

    // MARK: - Helper Methods

    private func findSwiftFiles(in url: URL) throws -> [URL] {
        var files: [URL] = []

        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) else {
            return files
        }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "swift" {
                files.append(fileURL)
            }
        }

        return files
    }

    private func findLineNumber(of keyword: String, in content: String) -> Int {
        let lines = content.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            if line.localizedCaseInsensitiveContains(keyword) {
                return index + 1
            }
        }
        return 0
    }

    private func determineSeverity(for keyword: String, in category: DataCategory) -> Severity {
        let highSeverityKeywords = ["IDFA", "advertisingIdentifier", "location", "health", "financial"]

        if highSeverityKeywords.contains(keyword) {
            return .high
        } else if category == .sensitive || category == .contactInfo {
            return .high
        } else {
            return .medium
        }
    }

    private func shouldTrack(for category: DataCategory) -> Bool {
        // Categories typically used for tracking
        return [.advertisingData, .analytics, .browsing, .searchHistory].contains(category)
    }

    private func isEphemeral(for category: DataCategory) -> Bool {
        // Data that is typically not stored long-term
        return [.browsing, .searchHistory].contains(category)
    }

    private func extractSDKName(from description: String) -> String? {
        let pattern = #"Third-party SDK: (.+?) -"#
        guard let range = description.range(of: pattern, options: .regularExpression) else { return nil }
        let match = description[range]
        let components = match.components(separatedBy: ": ")
        return components.count > 1 ? components[1].replacingOccurrences(of: " -", with: "") : nil
    }
}

// MARK: - Data Models

struct PrivacyManifest: Codable {
    let version: String
    let dataCollected: [DataCollectedEntry]
    let tracking: [TrackingEntry]
    let thirdPartySDKs: [ThirdPartySDKEntry]

    func generateJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.keyEncodingStrategy = .convertToSnakeCase

        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return json
    }
}

struct DataCollectedEntry: Codable {
    let dataCategory: DataCategory
    let purposes: [DataPurpose]
    let isLinked: Bool
    let isTracking: Bool
    let isEphemeral: Bool
}

struct TrackingEntry: Codable {
    let trackingDomain: String
    let isTrackingEnabled: Bool
}

struct ThirdPartySDKEntry: Codable {
    let name: String
    let privacyPolicyURL: URL?
    let purposes: [DataPurpose]
}

struct PrivacyAnalysisResult: Identifiable {
    let id = UUID()
    let type: AnalysisType
    let category: DataCategory
    let file: String
    let line: Int
    let description: String
    let severity: Severity
}

struct SDKPrivacyInfo {
    let collects: [DataCategory]
    let purpose: String
}

// MARK: - Enums

enum DataCategory: String, CaseIterable, Codable {
    case contactInfo = "NSPrivacyCollectedDataTypeContactInfo"
    case health = "NSPrivacyCollectedDataTypeHealth"
    case financial = "NSPrivacyCollectedDataTypeFinancial"
    case location = "NSPrivacyCollectedDataTypeLocation"
    case sensitive = "NSPrivacyCollectedDataTypeSensitive"
    case contacts = "NSPrivacyCollectedDataTypeContacts"
    case userContent = "NSPrivacyCollectedDataTypeUserContent"
    case browsing = "NSPrivacyCollectedDataTypeBrowsingHistory"
    case searchHistory = "NSPrivacyCollectedDataTypeSearchHistory"
    case productInteraction = "NSPrivacyCollectedDataTypeProductInteraction"
    case advertisingData = "NSPrivacyCollectedDataTypeAdvertisingData"
    case analytics = "NSPrivacyCollectedDataTypeAnalytics"
    case crashReporting = "NSPrivacyCollectedDataTypeCrashData"
    case performanceMonitoring = "NSPrivacyCollectedDataTypePerformanceData"
    case other = "NSPrivacyCollectedDataTypeOther"

    var displayName: String {
        switch self {
        case .contactInfo: return "Contact Info"
        case .health: return "Health"
        case .financial: return "Financial"
        case .location: return "Location"
        case .sensitive: return "Sensitive"
        case .contacts: return "Contacts"
        case .userContent: return "User Content"
        case .browsing: return "Browsing History"
        case .searchHistory: return "Search History"
        case .productInteraction: return "Product Interaction"
        case .advertisingData: return "Advertising Data"
        case .analytics: return "Analytics"
        case .crashReporting: return "Crash Reporting"
        case .performanceMonitoring: return "Performance Monitoring"
        case .other: return "Other"
        }
    }
}

enum DataPurpose: String, CaseIterable, Codable {
    case analytics = "NSPrivacyCollectedDataTypePurposeAnalytics"
    case advertising = "NSPrivacyCollectedDataTypePurposeAdvertising"
    case appFunctionality = "NSPrivacyCollectedDataTypePurposeAppFunctionality"
    case developersAdvertising = "NSPrivacyCollectedDataTypePurposeDevelopersAdvertising"
    case productPersonalization = "NSPrivacyCollectedDataTypePurposeProductPersonalization"

    var displayName: String {
        switch self {
        case .analytics: return "Analytics"
        case .advertising: return "Advertising"
        case .appFunctionality: return "App Functionality"
        case .developersAdvertising: return "Developer's Advertising"
        case .productPersonalization: return "Product Personalization"
        }
    }
}

enum TrackingType: String, CaseIterable {
    case analytics
    case advertising
    case crashReporting
    case performanceMonitoring
    case attribution
}

enum AnalysisType {
    case dataCollection
    case tracking
    case thirdPartySDK
}

enum Severity {
    case low
    case medium
    case high

    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}
