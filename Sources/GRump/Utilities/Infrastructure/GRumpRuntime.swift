import Foundation

/// Runtime environment probes. Used to avoid touching APIs that crash outside a real
/// app bundle — notably `UNUserNotificationCenter.current()`, which traps under the
/// XCTest / SPM command-line runner.
enum GRumpRuntime {
    /// True when running under XCTest or without an app bundle. In this mode, user
    /// notifications are unavailable and must be skipped (not just no-op'd lazily).
    static let isHeadless: Bool = {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        if NSClassFromString("XCTestCase") != nil { return true }
        if Bundle.main.bundleIdentifier == nil { return true }
        return false
    }()

    /// True when user notifications can be safely used.
    static var notificationsAvailable: Bool { !isHeadless }
}
