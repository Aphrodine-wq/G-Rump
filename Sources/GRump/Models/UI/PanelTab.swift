import SwiftUI

/// Panels available in the right-side icon sidebar.
enum PanelTab: String, CaseIterable, Identifiable {
    case chat
    case files
    case preview
    case simulator
    case git
    case tests
    case build
    case assets
    case localization
    case schema
    case profiling
    case logs
    case spm
    case xcode
    case docs
    case terminal
    case appstore
    case accessibility
    case memory
    case learning

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .files: return "folder.fill"
        case .preview: return "eye.fill"
        case .simulator: return "iphone"
        case .git: return "arrow.triangle.branch"
        case .tests: return "checkmark.diamond.fill"
        case .build: return "hammer.circle"
        case .assets: return "photo.stack.fill"
        case .localization: return "globe"
        case .schema: return "cylinder.split.1x2.fill"
        case .profiling: return "gauge.with.dots.needle.67percent"
        case .logs: return "doc.text.magnifyingglass"
        case .spm: return "shippingbox.fill"
        case .xcode: return "hammer.fill"
        case .docs: return "book.fill"
        case .terminal: return "terminal.fill"
        case .appstore: return "bag.fill"
        case .accessibility: return "figure.stand"
        case .memory: return "brain.head.profile"
        case .learning: return "graduationcap"
        }
    }

    var label: String {
        switch self {
        case .chat: return "Chat"
        case .files: return "Files"
        case .preview: return "Preview"
        case .simulator: return "Simulator"
        case .git: return "Git"
        case .tests: return "Tests"
        case .build: return "Build"
        case .assets: return "Assets"
        case .localization: return "Localization"
        case .schema: return "Schema"
        case .profiling: return "Profiling"
        case .logs: return "Logs"
        case .spm: return "Packages"
        case .xcode: return "Xcode"
        case .docs: return "Docs"
        case .terminal: return "Terminal"
        case .appstore: return "App Store"
        case .accessibility: return "A11y"
        case .memory: return "Memory"
        case .learning: return "Learning"
        }
    }

    /// Dock groups for the right panel icon sidebar, top to bottom:
    /// core workflow, Apple dev tools, content tools.
    /// Single source of truth — `RightPanelSidebar` renders exactly these,
    /// and a test asserts every case appears exactly once.
    static let dockGroups: [[PanelTab]] = [
        [.chat, .files, .git, .tests, .terminal, .memory, .learning],
        [.build, .preview, .simulator, .xcode, .spm, .profiling, .logs, .docs],
        [.assets, .localization, .schema, .appstore, .accessibility]
    ]

    var shortcut: String? {
        switch self {
        case .chat: return "1"
        case .files: return "2"
        case .preview: return "3"
        case .simulator: return "4"
        case .git: return "5"
        case .tests: return "6"
        case .terminal: return "7"
        case .spm: return "8"
        case .docs: return "9"
        case .memory: return "0"
        default: return nil
        }
    }
}
