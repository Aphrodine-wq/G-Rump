import Foundation

// MARK: - Workflow Preset (model + prompt + optional tool subset)

struct WorkflowPreset: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var modelRawValue: String
    var systemPrompt: String
    var toolAllowlist: [String]?
    var maxAgentSteps: Int?

    init(id: UUID = UUID(), name: String, modelRawValue: String, systemPrompt: String, toolAllowlist: [String]? = nil, maxAgentSteps: Int? = nil) {
        self.id = id
        self.name = name
        self.modelRawValue = modelRawValue
        self.systemPrompt = systemPrompt
        self.toolAllowlist = toolAllowlist
        self.maxAgentSteps = maxAgentSteps
    }

    var model: EnhancedAIModel? {
        AIModelRegistry.shared.getModel(by: modelRawValue)
    }
}

// MARK: - Storage

enum WorkflowPresetsStorage {
    private static let key = "GRumpWorkflowPresets"

    static func load() -> [WorkflowPreset] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([WorkflowPreset].self, from: data) else {
            return defaultPresets
        }
        return decoded
    }

    static func save(_ presets: [WorkflowPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static var defaultPresets: [WorkflowPreset] {
        [
            WorkflowPreset(
                name: "Refactor mode",
                modelRawValue: "claude-opus-4-8",
                systemPrompt: GRumpDefaults.defaultSystemPrompt + "\n\nFocus on refactoring: improve structure, reduce duplication, and maintain behavior. Prefer edit_file over write_file. Run tests after changes."
            ),
            WorkflowPreset(
                name: "Debug assistant",
                modelRawValue: "claude-sonnet-5",
                systemPrompt: GRumpDefaults.defaultSystemPrompt + "\n\nFocus on debugging: analyze error messages, trace execution, and propose minimal fixes. Use run_command to reproduce and verify."
            ),
            WorkflowPreset(
                name: "Read-only research",
                modelRawValue: "claude-opus-4-8",
                systemPrompt: GRumpDefaults.defaultSystemPrompt + "\n\nRead-only mode: only use read_file, list_directory, grep_search, web_search, read_url. Do not modify files or run commands.",
                toolAllowlist: ["read_file", "batch_read_files", "list_directory", "tree_view", "search_files", "grep_search", "file_info", "path_exists", "count_lines", "view_code_outline", "web_search", "read_url", "clipboard_read", "get_env"]
            ),
            WorkflowPreset(
                name: "Extended run",
                modelRawValue: "claude-fable-5",
                systemPrompt: GRumpDefaults.defaultSystemPrompt + "\n\nExtended autonomous run: work through the full task end-to-end without stopping. Use all available steps. Complete complex, multi-step changes before responding. Verify builds and tests before finishing.",
                maxAgentSteps: 150
            )
        ]
    }
}
