import Foundation

// MARK: - Xcode Project Inspector
//
// Nonisolated project inspection, extracted from XcodeProjectService so the
// build engine (BuildService) and the Xcode panel share one implementation.
// Everything here is safe to call off the main actor.

enum XcodeProjectInspector {

    struct ParseResult {
        let name: String
        let path: String
        let targets: [XcodeTarget]
        let schemes: [XcodeScheme]
        let configs: [XcodeBuildConfig]
    }

    /// Per-scheme/config settings the run pipeline needs (built product location
    /// and identity). Fetched via `xcodebuild -showBuildSettings -json`.
    struct BuildSettings: Equatable {
        let targetBuildDir: String
        let fullProductName: String
        let bundleId: String?
        let productName: String?

        var productPath: String {
            (targetBuildDir as NSString).appendingPathComponent(fullProductName)
        }
    }

    // MARK: - Project parsing (moved from XcodeProjectService)

    static func parse(dir: String) -> ParseResult {
        let fm = FileManager.default

        // Find .xcodeproj or .xcworkspace
        var projectPath = ""
        var projectName = ""

        if let contents = try? fm.contentsOfDirectory(atPath: dir) {
            // Prefer workspace
            if let workspace = contents.first(where: { $0.hasSuffix(".xcworkspace") && !$0.hasPrefix(".") }) {
                projectPath = (dir as NSString).appendingPathComponent(workspace)
                projectName = (workspace as NSString).deletingPathExtension
            } else if let project = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
                projectPath = (dir as NSString).appendingPathComponent(project)
                projectName = (project as NSString).deletingPathExtension
            }
        }

        guard !projectPath.isEmpty else {
            return ParseResult(name: "", path: "", targets: [], schemes: [], configs: [])
        }

        let targets = parsePbxproj(projectPath: projectPath)
        let schemes = parseSchemes(projectPath: projectPath)
        let configs = [
            XcodeBuildConfig(id: "Debug", name: "Debug"),
            XcodeBuildConfig(id: "Release", name: "Release")
        ]

        return ParseResult(
            name: projectName, path: projectPath,
            targets: targets, schemes: schemes, configs: configs
        )
    }

    static func parsePbxproj(projectPath: String) -> [XcodeTarget] {
        // If it's a workspace, find the embedded project
        var pbxprojPath: String
        if projectPath.hasSuffix(".xcworkspace") {
            let parent = (projectPath as NSString).deletingLastPathComponent
            let projectName = (projectPath as NSString).lastPathComponent
                .replacingOccurrences(of: ".xcworkspace", with: ".xcodeproj")
            pbxprojPath = (parent as NSString).appendingPathComponent(projectName)
            pbxprojPath = (pbxprojPath as NSString).appendingPathComponent("project.pbxproj")
        } else {
            pbxprojPath = (projectPath as NSString).appendingPathComponent("project.pbxproj")
        }

        guard let content = try? String(contentsOfFile: pbxprojPath, encoding: .utf8) else {
            return []
        }

        var targets: [XcodeTarget] = []

        // Parse PBXNativeTarget sections
        let lines = content.components(separatedBy: "\n")
        var inTargetSection = false
        var currentName = ""
        var currentProductType = ""
        var currentId = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.contains("/* Begin PBXNativeTarget section */") {
                inTargetSection = true
                continue
            }
            if trimmed.contains("/* End PBXNativeTarget section */") {
                inTargetSection = false
                continue
            }

            if inTargetSection {
                if trimmed.contains("isa = PBXNativeTarget") {
                    // Extract target ID from the line above (the section entry)
                    currentId = UUID().uuidString
                }

                if trimmed.hasPrefix("name = ") {
                    currentName = trimmed
                        .replacingOccurrences(of: "name = ", with: "")
                        .replacingOccurrences(of: ";", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                        .trimmingCharacters(in: .whitespaces)
                }

                if trimmed.hasPrefix("productType = ") {
                    currentProductType = trimmed
                        .replacingOccurrences(of: "productType = ", with: "")
                        .replacingOccurrences(of: ";", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                        .trimmingCharacters(in: .whitespaces)

                    let targetType = mapProductType(currentProductType)

                    if !currentName.isEmpty {
                        targets.append(XcodeTarget(
                            id: currentId.isEmpty ? currentName : currentId,
                            name: currentName,
                            type: targetType,
                            bundleId: nil,
                            deploymentTarget: nil
                        ))
                    }
                    currentName = ""
                    currentProductType = ""
                    currentId = ""
                }
            }
        }

        return targets
    }

    static func mapProductType(_ productType: String) -> XcodeTarget.TargetType {
        if productType.contains("application") { return .app }
        if productType.contains("framework") { return .framework }
        if productType.contains("static") { return .staticLibrary }
        if productType.contains("unit-test") { return .unitTest }
        if productType.contains("ui-testing") { return .uiTest }
        if productType.contains("app-extension") || productType.contains("appex") { return .appExtension }
        if productType.contains("watchkit") { return .watchApp }
        if productType.contains("widget") { return .widgetExtension }
        return .unknown
    }

    static func parseSchemes(projectPath: String) -> [XcodeScheme] {
        let fm = FileManager.default
        var schemes: [XcodeScheme] = []

        // Check shared schemes
        let sharedSchemesDir = (projectPath as NSString).appendingPathComponent("xcshareddata/xcschemes")

        if let files = try? fm.contentsOfDirectory(atPath: sharedSchemesDir) {
            for file in files where file.hasSuffix(".xcscheme") {
                let name = (file as NSString).deletingPathExtension
                schemes.append(XcodeScheme(id: name, name: name, isShared: true))
            }
        }

        // Also try xcodebuild -list for schemes
        if schemes.isEmpty {
            #if os(macOS)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
            process.arguments = ["-list", "-json"]
            let dir = (projectPath as NSString).deletingLastPathComponent
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            try? process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let projectInfo = json["project"] as? [String: Any] ?? json["workspace"] as? [String: Any] ?? [:]
                if let schemeNames = projectInfo["schemes"] as? [String] {
                    schemes = schemeNames.map { XcodeScheme(id: $0, name: $0, isShared: false) }
                }
            }
            #endif
        }

        return schemes
    }

    // MARK: - Build settings

    /// Pure parser for `xcodebuild -showBuildSettings -json` output (an array of
    /// `{action, target, buildSettings}` entries — the first entry wins).
    static func parseBuildSettings(json data: Data) -> BuildSettings? {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = array.first,
              let settings = first["buildSettings"] as? [String: Any],
              let targetBuildDir = settings["TARGET_BUILD_DIR"] as? String,
              let fullProductName = settings["FULL_PRODUCT_NAME"] as? String else {
            return nil
        }
        return BuildSettings(
            targetBuildDir: targetBuildDir,
            fullProductName: fullProductName,
            bundleId: settings["PRODUCT_BUNDLE_IDENTIFIER"] as? String,
            productName: settings["PRODUCT_NAME"] as? String
        )
    }

    #if os(macOS)
    /// Fetches build settings for a scheme + configuration. Runs xcodebuild off
    /// the calling actor with a 10s watchdog (showBuildSettings can hang on
    /// damaged projects). Returns nil on timeout, non-zero exit, or parse failure.
    static func buildSettings(
        containerPath: String,
        isWorkspace: Bool,
        scheme: String,
        configuration: String
    ) async -> BuildSettings? {
        let task = Task.detached(priority: .utility) { () -> BuildSettings? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
            process.arguments = [
                isWorkspace ? "-workspace" : "-project", containerPath,
                "-scheme", scheme,
                "-configuration", configuration,
                "-showBuildSettings", "-json"
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                return nil
            }

            let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10, execute: killer)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            killer.cancel()

            guard process.terminationStatus == 0 else { return nil }
            return parseBuildSettings(json: data)
        }
        return await task.value
    }
    #endif
}
