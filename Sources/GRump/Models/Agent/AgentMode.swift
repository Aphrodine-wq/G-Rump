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

// MARK: - Agent Mode (Chat, Plan, Build, Debate, Spec)

enum AgentMode: String, CaseIterable, Identifiable, Codable {
    case standard
    case plan
    case fullStack
    case argue
    case spec
    case parallel
    case speculative

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Chat"
        case .plan: return "Plan"
        case .fullStack: return "Build"
        case .argue: return "Debate"
        case .spec: return "Spec"
        case .parallel: return "Parallel"
        case .speculative: return "Explore"
        }
    }

    var icon: String {
        switch self {
        case .standard: return "text.bubble"
        case .plan: return "list.bullet.clipboard"
        case .fullStack: return "hammer.fill"
        case .argue: return "bubble.left.and.bubble.right"
        case .spec: return "doc.text.magnifyingglass"
        case .parallel: return "arrow.triangle.branch"
        case .speculative: return "point.3.connected.trianglepath.dotted"
        }
    }

    var description: String {
        switch self {
        case .standard: return "Direct chat with full tool access and autonomous execution."
        case .plan: return "Creates a detailed plan before writing any code."
        case .fullStack: return "Builds complete features end-to-end across the full stack."
        case .argue: return "Debates both sides before recommending an approach."
        case .spec: return "Asks clarifying questions to refine requirements before acting."
        case .parallel: return "Runs multiple sub-agents in parallel for complex tasks."
        case .speculative: return "Explores 2-3 competing approaches in parallel and picks the winner."
        }
    }

    /// Per-mode accent color for minimal visual differentiation.
    var modeAccentColor: Color {
        switch self {
        case .standard:    return .purple
        case .plan:        return .blue
        case .fullStack:   return .green
        case .argue:       return .orange
        case .spec:        return .teal
        case .parallel:    return .indigo
        case .speculative: return .yellow
        }
    }

    var toastMessage: String {
        switch self {
        case .standard: return "Switched to Chat mode"
        case .plan: return "Switched to Plan mode"
        case .fullStack: return "Switched to Build mode"
        case .argue: return "Switched to Debate mode"
        case .spec: return "Switched to Spec mode"
        case .parallel: return "Switched to Parallel mode"
        case .speculative: return "Switched to Explore mode"
        }
    }

    /// Maps the agent mode to the appropriate `LogoMood` for the FrownyFaceLogo.
    /// Single source of truth — used by both `MessageRow` and `PremiumStreamingRow`.
    var logoMood: LogoMood {
        switch self {
        case .standard, .parallel, .speculative: return .neutral
        case .plan: return .thinking
        case .fullStack: return .happy
        case .argue: return .error
        case .spec: return .thinking
        }
    }
}
