import XCTest
import SwiftUI
@testable import GRump

final class PrivacyManifestGeneratorTests: XCTestCase {

    // MARK: - DataCategory

    func testAllDataCategoriesCount() {
        XCTAssertEqual(DataCategory.allCases.count, 15)
    }

    func testDataCategoryRawValuesStartWithNSPrivacy() {
        for category in DataCategory.allCases {
            XCTAssertTrue(category.rawValue.hasPrefix("NSPrivacyCollectedDataType"),
                "\(category) rawValue should start with NSPrivacyCollectedDataType")
        }
    }

    func testDataCategoryDisplayNames() {
        for category in DataCategory.allCases {
            XCTAssertFalse(category.displayName.isEmpty, "\(category) missing displayName")
        }
    }

    func testSpecificDisplayNames() {
        XCTAssertEqual(DataCategory.contactInfo.displayName, "Contact Info")
        XCTAssertEqual(DataCategory.health.displayName, "Health")
        XCTAssertEqual(DataCategory.location.displayName, "Location")
        XCTAssertEqual(DataCategory.crashReporting.displayName, "Crash Reporting")
        XCTAssertEqual(DataCategory.other.displayName, "Other")
    }

    func testDataCategoryCodable() throws {
        for category in DataCategory.allCases {
            let data = try JSONEncoder().encode(category)
            let decoded = try JSONDecoder().decode(DataCategory.self, from: data)
            XCTAssertEqual(decoded, category)
        }
    }

    // MARK: - DataPurpose

    func testAllDataPurposesCount() {
        XCTAssertEqual(DataPurpose.allCases.count, 5)
    }

    func testDataPurposeDisplayNames() {
        for purpose in DataPurpose.allCases {
            XCTAssertFalse(purpose.displayName.isEmpty, "\(purpose) missing displayName")
        }
    }

    func testDataPurposeCodable() throws {
        for purpose in DataPurpose.allCases {
            let data = try JSONEncoder().encode(purpose)
            let decoded = try JSONDecoder().decode(DataPurpose.self, from: data)
            XCTAssertEqual(decoded, purpose)
        }
    }

    // MARK: - TrackingType

    func testAllTrackingTypesCount() {
        XCTAssertEqual(TrackingType.allCases.count, 5)
    }

    func testTrackingTypeRawValues() {
        let expected = ["analytics", "advertising", "crashReporting", "performanceMonitoring", "attribution"]
        let actual = TrackingType.allCases.map(\.rawValue)
        XCTAssertEqual(Set(actual), Set(expected))
    }

    // MARK: - Severity

    func testSeverityColors() {
        XCTAssertNotEqual(Severity.low.color.description, Color.clear.description)
        XCTAssertNotEqual(Severity.medium.color.description, Color.clear.description)
        XCTAssertNotEqual(Severity.high.color.description, Color.clear.description)
    }

    func testSeverityColorsAreDistinct() {
        let lowDesc = Severity.low.color.description
        let medDesc = Severity.medium.color.description
        let highDesc = Severity.high.color.description
        XCTAssertNotEqual(lowDesc, medDesc)
        XCTAssertNotEqual(medDesc, highDesc)
    }

    // MARK: - PrivacyManifest

    func testEmptyManifestGeneratesJSON() {
        let manifest = PrivacyManifest(
            version: "1.0.0",
            dataCollected: [],
            tracking: [],
            thirdPartySDKs: []
        )
        let json = manifest.generateJSON()
        XCTAssertFalse(json.isEmpty)
        XCTAssertTrue(json.contains("1.0.0"))
    }

    func testManifestWithDataGeneratesJSON() {
        let manifest = PrivacyManifest(
            version: "1.0.0",
            dataCollected: [
                DataCollectedEntry(
                    dataCategory: .analytics,
                    purposes: [.analytics],
                    isLinked: false,
                    isTracking: false,
                    isEphemeral: true
                )
            ],
            tracking: [],
            thirdPartySDKs: []
        )
        let json = manifest.generateJSON()
        XCTAssertTrue(json.lowercased().contains("analytics"))
    }

    func testManifestCodable() throws {
        let manifest = PrivacyManifest(
            version: "1.0.0",
            dataCollected: [],
            tracking: [TrackingEntry(trackingDomain: "test.com", isTrackingEnabled: true)],
            thirdPartySDKs: [ThirdPartySDKEntry(name: "TestSDK", privacyPolicyURL: nil, purposes: [.analytics])]
        )
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(PrivacyManifest.self, from: data)
        XCTAssertEqual(decoded.version, "1.0.0")
        XCTAssertEqual(decoded.tracking.count, 1)
        XCTAssertEqual(decoded.thirdPartySDKs.count, 1)
    }

    // MARK: - PrivacyAnalysisResult

    func testAnalysisResultCreation() {
        let result = PrivacyAnalysisResult(
            type: .dataCollection,
            category: .location,
            file: "LocationService.swift",
            line: 42,
            description: "Uses CLLocationManager",
            severity: .high
        )
        XCTAssertNotNil(result.id)
        XCTAssertEqual(result.file, "LocationService.swift")
        XCTAssertEqual(result.line, 42)
        XCTAssertEqual(result.severity, .high)
    }

    // MARK: - SDKPrivacyInfo

    func testSDKPrivacyInfoCreation() {
        let info = SDKPrivacyInfo(
            collects: [.analytics, .crashReporting],
            purpose: "Error monitoring"
        )
        XCTAssertEqual(info.collects.count, 2)
        XCTAssertEqual(info.purpose, "Error monitoring")
    }

    // MARK: - DataCollectedEntry

    func testDataCollectedEntryCodable() throws {
        let entry = DataCollectedEntry(
            dataCategory: .health,
            purposes: [.appFunctionality, .analytics],
            isLinked: true,
            isTracking: false,
            isEphemeral: false
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(DataCollectedEntry.self, from: data)
        XCTAssertEqual(decoded.dataCategory, .health)
        XCTAssertEqual(decoded.purposes.count, 2)
        XCTAssertTrue(decoded.isLinked)
        XCTAssertFalse(decoded.isTracking)
    }

    // MARK: - TrackingEntry

    func testTrackingEntryCodable() throws {
        let entry = TrackingEntry(trackingDomain: "example.com", isTrackingEnabled: false)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(TrackingEntry.self, from: data)
        XCTAssertEqual(decoded.trackingDomain, "example.com")
        XCTAssertFalse(decoded.isTrackingEnabled)
    }

    // MARK: - ThirdPartySDKEntry

    func testThirdPartySDKEntryCodable() throws {
        let entry = ThirdPartySDKEntry(
            name: "Firebase",
            privacyPolicyURL: URL(string: "https://firebase.google.com/privacy"),
            purposes: [.analytics, .advertising]
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ThirdPartySDKEntry.self, from: data)
        XCTAssertEqual(decoded.name, "Firebase")
        XCTAssertNotNil(decoded.privacyPolicyURL)
        XCTAssertEqual(decoded.purposes.count, 2)
    }
}
