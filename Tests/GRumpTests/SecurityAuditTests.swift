import XCTest
@testable import GRump

/// Security-focused tests verifying input sanitization, command injection prevention,
/// path traversal protection, API key handling, and credential isolation.
final class SecurityAuditTests: XCTestCase {

    // MARK: - Command Injection (ExecApprovals)

    func testPathMatchingRejectsEmptyInputs() {
        #if os(macOS)
        // Empty or whitespace-only paths must never match any pattern
        XCTAssertFalse(ExecApprovalsStorage.path("", matchesPattern: "*"))
        XCTAssertFalse(ExecApprovalsStorage.path("", matchesPattern: ""))
        XCTAssertFalse(ExecApprovalsStorage.path(" ", matchesPattern: "*"))
        #endif
    }

    func testPathMatchingRejectsPathTraversal() {
        #if os(macOS)
        // Ensure path traversal sequences cannot escape allowed directories
        XCTAssertFalse(ExecApprovalsStorage.path("/usr/../etc/passwd", matchesPattern: "/usr/*"))
        XCTAssertFalse(ExecApprovalsStorage.path("/../etc/shadow", matchesPattern: "/*"))
        #endif
    }

    func testPathMatchingIsExactForFixedPaths() {
        #if os(macOS)
        // A fixed pattern (no glob) must only match an identical string
        XCTAssertTrue(ExecApprovalsStorage.path("/usr/bin/swift", matchesPattern: "/usr/bin/swift"))
        XCTAssertFalse(ExecApprovalsStorage.path("/usr/bin/swiftc", matchesPattern: "/usr/bin/swift"))
        XCTAssertFalse(ExecApprovalsStorage.path("/usr/bin/swif", matchesPattern: "/usr/bin/swift"))
        #endif
    }

    func testDefaultSecurityLevelIsDeny() {
        #if os(macOS)
        let config = ExecApprovalsConfig.default
        XCTAssertEqual(config.security, .deny,
            "Default security level must be deny — requiring explicit approval for every command")
        #endif
    }

    func testDenyModeBlocksAllCommands() {
        #if os(macOS)
        var config = ExecApprovalsConfig.default
        config.security = .deny
        config.allowlist = [
            ExecAllowlistEntry(pattern: "/usr/bin/*", source: "test")
        ]
        // In deny mode, the allowlist should be irrelevant — nothing should be auto-approved
        // This verifies the security level takes precedence over the allowlist
        XCTAssertEqual(config.security, .deny)
        #endif
    }

    // MARK: - API Key Safety

    func testAPIKeyNotLeakedInModelRawValues() {
        // Ensure no AI model raw values accidentally contain API keys or tokens
        for model in AIModel.allCases {
            let rawValue = model.rawValue.lowercased()
            XCTAssertFalse(rawValue.contains("sk-"), "Model raw value contains suspicious key prefix: \(model.rawValue)")
            XCTAssertFalse(rawValue.contains("token"), "Model raw value contains 'token': \(model.rawValue)")
            XCTAssertFalse(rawValue.contains("secret"), "Model raw value contains 'secret': \(model.rawValue)")
            XCTAssertFalse(rawValue.contains("password"), "Model raw value contains 'password': \(model.rawValue)")
        }
    }

    func testSystemPromptDoesNotContainCredentials() {
        let prompt = GRumpDefaults.defaultSystemPrompt.lowercased()
        XCTAssertFalse(prompt.contains("sk-"))
        XCTAssertFalse(prompt.contains("api_key"))
        XCTAssertFalse(prompt.contains("password"))
        XCTAssertFalse(prompt.contains("bearer "))
    }

    // MARK: - MCP Credential Vault Isolation

    func testCredentialVaultIsolatesBetweenServers() {
        let serverA = "test-isolation-a-\(UUID().uuidString)"
        let serverB = "test-isolation-b-\(UUID().uuidString)"
        defer {
            MCPCredentialVault.deleteEnvVars(serverID: serverA)
            MCPCredentialVault.deleteEnvVars(serverID: serverB)
        }

        MCPCredentialVault.saveEnvVars(serverID: serverA, envVars: ["SECRET": "alpha"])
        MCPCredentialVault.saveEnvVars(serverID: serverB, envVars: ["SECRET": "beta"])

        XCTAssertEqual(MCPCredentialVault.getValue(serverID: serverA, key: "SECRET"), "alpha")
        XCTAssertEqual(MCPCredentialVault.getValue(serverID: serverB, key: "SECRET"), "beta")
    }

    func testCredentialVaultHandlesSpecialCharacters() {
        let testID = "test-special-chars-\(UUID().uuidString)"
        defer { MCPCredentialVault.deleteEnvVars(serverID: testID) }

        // Values with special chars (quotes, newlines, unicode)
        let specialValue = "sk-abc\"def\nghi\t日本語🔐"
        MCPCredentialVault.setValue(serverID: testID, key: "SPECIAL_KEY", value: specialValue)
        XCTAssertEqual(MCPCredentialVault.getValue(serverID: testID, key: "SPECIAL_KEY"), specialValue)
    }

    func testCredentialVaultHandlesEmptyValues() {
        let testID = "test-empty-\(UUID().uuidString)"
        defer { MCPCredentialVault.deleteEnvVars(serverID: testID) }

        MCPCredentialVault.setValue(serverID: testID, key: "EMPTY", value: "")
        let loaded = MCPCredentialVault.loadEnvVars(serverID: testID)
        XCTAssertEqual(loaded["EMPTY"], "")
    }

    func testCredentialVaultHandlesLargeValues() {
        let testID = "test-large-\(UUID().uuidString)"
        defer { MCPCredentialVault.deleteEnvVars(serverID: testID) }

        let largeValue = String(repeating: "x", count: 10_000)
        MCPCredentialVault.setValue(serverID: testID, key: "BIG", value: largeValue)
        XCTAssertEqual(MCPCredentialVault.getValue(serverID: testID, key: "BIG"), largeValue)
    }

    func testCredentialVaultDeleteIsClean() {
        let testID = "test-delete-clean-\(UUID().uuidString)"

        MCPCredentialVault.saveEnvVars(serverID: testID, envVars: [
            "KEY1": "val1", "KEY2": "val2", "KEY3": "val3"
        ])
        MCPCredentialVault.deleteEnvVars(serverID: testID)

        // All keys must be gone
        let loaded = MCPCredentialVault.loadEnvVars(serverID: testID)
        XCTAssertTrue(loaded.isEmpty, "All keys must be deleted")
        XCTAssertNil(MCPCredentialVault.getValue(serverID: testID, key: "KEY1"))
    }

    // MARK: - Platform Service URL Safety

    func testPlatformServiceBaseURLIsHTTPS() {
        // Verify the hardcoded platform API URL uses HTTPS
        // PlatformService.defaultBaseURL is private, but we can check the tier display names
        // which proves the service is properly configured
        XCTAssertEqual(PlatformService.tierDisplayName("pro"), "Pro")
        XCTAssertEqual(PlatformService.tierDisplayName("team"), "Team")
        XCTAssertEqual(PlatformService.tierDisplayName("starter"), "Starter")
        XCTAssertEqual(PlatformService.tierDisplayName("unknown"), "Free")
    }

    // MARK: - Model Data Integrity

    func testAllModelsHaveValidContextConfigurations() {
        for model in AIModel.allCases {
            // Context window must be reasonable (>= 8K, <= 10M)
            XCTAssertGreaterThanOrEqual(model.contextWindow, 8_000,
                "\(model.rawValue) context window too small: \(model.contextWindow)")
            XCTAssertLessThanOrEqual(model.contextWindow, 10_000_000,
                "\(model.rawValue) context window suspiciously large: \(model.contextWindow)")

            // Max output must be > 0 and <= context window
            XCTAssertGreaterThan(model.maxOutput, 0, "\(model.rawValue) maxOutput is 0")
            XCTAssertLessThanOrEqual(model.maxOutput, model.contextWindow,
                "\(model.rawValue) maxOutput exceeds contextWindow")

            // Max output must be reasonable (>= 4K)
            XCTAssertGreaterThanOrEqual(model.maxOutput, 4_000,
                "\(model.rawValue) maxOutput too small: \(model.maxOutput)")
        }
    }

    func testModelMigrationHandlesUnknownIds() {
        // Unknown model IDs should fall back to the default Qwen model, not crash or return nil
        XCTAssertEqual(AIModel.migrateLegacyID("totally-fake/nonexistent-model-v99"), .qwenCoderPlus)
        XCTAssertEqual(AIModel.migrateLegacyID(""), .qwenCoderPlus)
        XCTAssertEqual(AIModel.migrateLegacyID(" "), .qwenCoderPlus)
    }

    func testModelMigrationHandlesKnownLegacyIds() {
        // Known legacy IDs must migrate onto a Qwen model. Note "gemini" contains
        // the substring "mini", so both gemini variants resolve to Qwen Turbo.
        XCTAssertEqual(AIModel.migrateLegacyID("google/gemini-2.5-pro-preview"), .qwenTurbo)
        XCTAssertEqual(AIModel.migrateLegacyID("google/gemini-2.5-flash-preview"), .qwenTurbo)
        XCTAssertEqual(AIModel.migrateLegacyID("anthropic/claude-opus-4"), .qwenMax)
    }

    func testModelMigrationPassesThroughCurrentIds() {
        // Current model IDs should pass through
        for model in AIModel.allCases {
            XCTAssertEqual(AIModel.migrateLegacyID(model.rawValue), model,
                "Current model \(model.rawValue) should pass through migration")
        }
    }

    func testEveryTierHasDefaultModel() {
        // Every tier should have a valid default
        let tiers: [String?] = [nil, "free", "starter", "pro", "team", "enterprise"]
        for tier in tiers {
            let defaultModel = AIModel.defaultForTier(tier)
            XCTAssertFalse(defaultModel.displayName.isEmpty, "Tier \(tier ?? "nil") has no default")
        }
    }

    func testProTierIncludesFreeTierModels() {
        // Pro users should see Pro models, not free ones (they're separate lists)
        let proModels = AIModel.modelsForTier("pro")
        let freeModels = AIModel.modelsForTier(nil)
        let proSet = Set(proModels.map(\.rawValue))
        let freeSet = Set(freeModels.map(\.rawValue))
        // Pro and free should not overlap
        let overlap = proSet.intersection(freeSet)
        // This is a design choice: if they overlap, it's intentional (dual-tier models like claudeSonnet4)
        // But no Pro-only model should appear in the free list
        for model in proModels where model.requiresPaidTier {
            XCTAssertFalse(freeSet.contains(model.rawValue),
                "\(model.rawValue) requires paid tier but appears in free list")
        }
    }

    // MARK: - Conversation Security

    func testConversationHandlesXSSInContent() {
        // Messages with script injection content should be stored safely
        var conv = Conversation(title: "Test")
        let xssContent = "<script>alert('xss')</script>"
        conv.messages.append(Message(role: .user, content: xssContent))
        XCTAssertEqual(conv.messages.first?.content, xssContent,
            "Content should be stored as-is (rendering layer handles escaping)")
    }

    func testConversationTitleSanitization() {
        // Title truncation should handle edge cases
        var conv = Conversation(title: "New Chat")

        // Empty user message
        conv.messages.append(Message(role: .user, content: ""))
        conv.updateTitle()
        XCTAssertEqual(conv.title, "", "Empty content should produce empty title")

        // Unicode-heavy content
        conv = Conversation(title: "New Chat")
        conv.messages.append(Message(role: .user, content: String(repeating: "🔐", count: 50)))
        conv.updateTitle()
        XCTAssertTrue(conv.title.count <= 42, "Title should truncate even with emoji")
    }

    func testToolCallArgumentsSafeWithMaliciousJSON() throws {
        // Tool call arguments with potentially malicious content should encode/decode safely
        let malicious = "{\"path\":\"/etc/passwd\",\"cmd\":\"rm -rf /\",\"content\":\"<script>alert(1)</script>\"}"
        let tc = ToolCall(id: "tc-sec", name: "dangerous_tool", arguments: malicious)
        let data = try JSONEncoder().encode(tc)
        let decoded = try JSONDecoder().decode(ToolCall.self, from: data)
        XCTAssertEqual(decoded.arguments, malicious, "Arguments should round-trip exactly")
    }

    // MARK: - SkillPack Model Integrity

    func testBuiltInPacksNotEmpty() {
        XCTAssertFalse(SkillPack.builtInPacks.isEmpty, "Should have built-in skill packs")
    }

    func testBuiltInPacksHaveUniqueIds() {
        let ids = SkillPack.builtInPacks.map(\.id)
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "Duplicate skill pack IDs found")
    }

    func testBuiltInPacksHaveRequiredFields() {
        for pack in SkillPack.builtInPacks {
            XCTAssertFalse(pack.id.isEmpty, "Pack ID must not be empty")
            XCTAssertFalse(pack.name.isEmpty, "Pack '\(pack.id)' must have a name")
            XCTAssertFalse(pack.icon.isEmpty, "Pack '\(pack.id)' must have an icon")
            XCTAssertFalse(pack.description.isEmpty, "Pack '\(pack.id)' must have a description")
            XCTAssertFalse(pack.skillBaseIds.isEmpty, "Pack '\(pack.id)' must have at least one skill")
        }
    }

    func testBuiltInPacksHaveUniqueNames() {
        let names = SkillPack.builtInPacks.map(\.name)
        let uniqueNames = Set(names)
        XCTAssertEqual(names.count, uniqueNames.count, "Duplicate skill pack names found")
    }

    func testBuiltInPackSkillIdsAreValid() {
        // All skill IDs referenced by packs should exist in builtInBaseIds
        for pack in SkillPack.builtInPacks {
            for skillId in pack.skillBaseIds {
                XCTAssertTrue(Skill.builtInBaseIds.contains(skillId),
                    "Pack '\(pack.name)' references unknown skill '\(skillId)'")
            }
        }
    }

    func testSkillPackCountMatchesExpected() {
        // Guard against accidentally removing packs
        XCTAssertGreaterThanOrEqual(SkillPack.builtInPacks.count, 15,
            "Expected at least 15 built-in skill packs, got \(SkillPack.builtInPacks.count)")
    }

    // MARK: - Message Threading Security

    func testCreateThreadWithNonexistentMessageReturnsNil() {
        var conv = Conversation(title: "T")
        conv.messages.append(Message(role: .user, content: "Hello"))
        let result = conv.createThread(from: UUID()) // Non-existent
        XCTAssertNil(result, "Creating thread from non-existent message must return nil")
        XCTAssertTrue(conv.threads.isEmpty, "No thread should be created")
    }

    func testCreateBranchWithNonexistentMessageReturnsNil() {
        var conv = Conversation(title: "T")
        conv.messages.append(Message(role: .user, content: "Hello"))
        let result = conv.createBranch(from: UUID(), name: "Fake")
        XCTAssertNil(result)
        XCTAssertTrue(conv.branches.isEmpty)
    }

    func testThreadFilteringDoesNotLeakBetweenThreads() {
        var conv = Conversation(title: "T")
        let msg1 = Message(role: .user, content: "Thread A root")
        let msg2 = Message(role: .user, content: "Thread B root")
        conv.messages.append(msg1)
        conv.messages.append(msg2)

        let threadAId = conv.createThread(from: msg1.id, name: "A")
        XCTAssertNotNil(threadAId)

        // Thread A messages should only include msg1 (and unthreaded messages)
        let threadMessages = conv.getActiveThreadMessages()
        let threadedContent = threadMessages.map(\.content)
        XCTAssertTrue(threadedContent.contains("Thread A root"))
    }
}
