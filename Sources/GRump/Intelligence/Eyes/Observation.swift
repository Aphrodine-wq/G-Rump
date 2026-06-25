import Foundation

/// A single screen observation: what was on-screen at a moment, already redacted.
/// Raw screenshots are never stored — only this redacted, classified summary.
struct Observation: Sendable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let app: String
    let windowTitle: String
    let phash: UInt64
    let redactedText: String
    let project: String
    let activity: String
    let entities: [String]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        app: String,
        windowTitle: String,
        phash: UInt64,
        redactedText: String,
        project: String,
        activity: String,
        entities: [String]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.app = app
        self.windowTitle = windowTitle
        self.phash = phash
        self.redactedText = redactedText
        self.project = project
        self.activity = activity
        self.entities = entities
    }
}
