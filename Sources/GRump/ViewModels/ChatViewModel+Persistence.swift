import Foundation

// MARK: - Persistence Extension
//
// Contains conversation file I/O (save, load), flush sync,
// and the conversations file URL resolution.
// Extracted from ChatViewModel.swift for maintainability.

extension ChatViewModel {

    // MARK: - Persistence

    static var conversationsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent(appDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("conversations.json")
    }

    func saveConversations() {
        do {
            let data = try JSONEncoder().encode(conversations)
            try data.write(to: Self.conversationsFileURL, options: .atomic)
        } catch {
            GRumpLogger.persistence.error("Failed to save conversations: \(error.localizedDescription)")
        }
    }

    func loadConversations() {
        let url = Self.conversationsFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            conversations = try JSONDecoder().decode([Conversation].self, from: data)
        } catch {
            GRumpLogger.persistence.error("Failed to load conversations: \(error.localizedDescription)")
        }
    }

    /// Immediately flush any pending conversation save.
    func flushSync() {
        guard syncDirty else { return }
        syncDirty = false
        syncDebounceTask?.cancel()
        saveConversations()
    }
}
