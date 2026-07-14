import Foundation
import SwiftUI

// MARK: - System Run Approval

#if os(macOS)
enum SystemRunApprovalResponse {
    case allowOnce
    case allowAlways
    case deny
}
#endif

// MARK: - Agent Mode (Plan, Build, Spec)

enum AgentMode: String, CaseIterable, Identifiable, Codable {
    case plan
    case fullStack
    case spec

    var id: String { rawValue }

    /// The next mode in declaration order, wrapping around. Drives ⇧⇥ cycling.
    var next: AgentMode {
        let all = AgentMode.allCases
        let index = all.firstIndex(of: self) ?? all.startIndex
        return all[(index + 1) % all.count]
    }

    var displayName: String {
        switch self {
        case .plan: return "Plan"
        case .fullStack: return "Build"
        case .spec: return "Spec"
        }
    }

    var icon: String {
        switch self {
        case .plan: return "list.bullet.clipboard"
        case .fullStack: return "hammer.fill"
        case .spec: return "doc.text.magnifyingglass"
        }
    }

    var description: String {
        switch self {
        case .plan: return "Creates a detailed plan before writing any code."
        case .fullStack: return "Builds complete features end-to-end across the full stack."
        case .spec: return "Asks clarifying questions to refine requirements before acting."
        }
    }

    /// Per-mode accent color for minimal visual differentiation.
    var modeAccentColor: Color {
        switch self {
        case .plan:        return .blue
        case .fullStack:   return .green
        case .spec:        return .teal
        }
    }

    var toastMessage: String {
        switch self {
        case .plan: return "Switched to Plan mode"
        case .fullStack: return "Switched to Build mode"
        case .spec: return "Switched to Spec mode"
        }
    }

    /// Maps the agent mode to the appropriate `LogoMood` for the FrownyFaceLogo.
    /// Single source of truth — used by both `MessageRow` and `PremiumStreamingRow`.
    var logoMood: LogoMood {
        switch self {
        case .plan: return .thinking
        case .fullStack: return .happy
        case .spec: return .thinking
        }
    }
}
