import OSLog

/// Centralized logging for G-Rump using Apple's unified logging system.
/// All subsystem logs are visible in Console.app under "com.grump.app".
enum GRumpLogger {
    static let general    = Logger(subsystem: "com.grump.app", category: "general")
    static let spotlight  = Logger(subsystem: "com.grump.app", category: "spotlight")
    static let persistence = Logger(subsystem: "com.grump.app", category: "persistence")
    static let ai         = Logger(subsystem: "com.grump.app", category: "ai")
    static let liveActivity = Logger(subsystem: "com.grump.app", category: "liveActivity")
    static let notifications = Logger(subsystem: "com.grump.app", category: "notifications")
    static let coreml     = Logger(subsystem: "com.grump.app", category: "coreml")
    static let capture    = Logger(subsystem: "com.grump.app", category: "capture")
    static let skills     = Logger(subsystem: "com.grump.app", category: "skills")
    static let migration  = Logger(subsystem: "com.grump.app", category: "migration")
    static let memory     = Logger(subsystem: "com.grump.app", category: "memory")
    static let proactive  = Logger(subsystem: "com.grump.app", category: "proactive")
    static let brain      = Logger(subsystem: "com.grump.app", category: "brain")
}
