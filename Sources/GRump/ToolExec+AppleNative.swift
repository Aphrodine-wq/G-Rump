import Foundation
#if os(macOS)
import AppKit
import CoreImage
import Vision
import Speech
import AVFoundation
import Contacts
import EventKit
import PDFKit
#endif

// MARK: - Apple-Native Tool Execution
// Handlers for spotlight_search, keychain_read/store, calendar_events, reminders_list,
// contacts_search, speech_transcribe, ocr_extract, image_classify, shortcuts_run,
// system_appearance, xcodebuild, xcrun_simctl, swift_format, swift_lint, swift_package,
// pdf_extract, tts_speak, qr_generate, websocket_send, graphql_query, bonjour_discover

extension ChatViewModel {

    // MARK: - Spotlight Search

    func executeSpotlightSearch(_ args: [String: Any]) async -> String {
        #if os(macOS)
        guard let query = args["query"] as? String else { return "Error: missing query" }
        let limit = args["limit"] as? Int ?? 20
        var processArgs: [String] = []
        if let directory = args["directory"] as? String {
            let resolved = resolvePath(directory)
            processArgs.append(contentsOf: ["-onlyin", resolved])
        }
        processArgs.append(query)
        let result = await runProcess(executablePath: "/usr/bin/mdfind", arguments: processArgs, cwd: nil, stdoutLimitLines: limit)
        return result.isEmpty ? "No results found for '\(query)'" : result
        #else
        return "Error: Spotlight search is only available on macOS"
        #endif
    }

    // MARK: - Keychain

    func executeKeychainRead(_ args: [String: Any]) -> String {
        #if os(macOS)
        guard let key = args["key"] as? String else { return "Error: missing key" }
        let service = args["service"] as? String ?? "com.grump.agent"
        guard service.hasPrefix("com.grump.") else {
            return "Error: can only read keychain items under com.grump.* service"
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            if status == errSecItemNotFound {
                return "No keychain item found for key '\(key)' in service '\(service)'"
            }
            return "Error: Keychain read failed (status: \(status))"
        }
        return value
        #else
        return "Error: Keychain access is only available on macOS"
        #endif
    }

    func executeKeychainStore(_ args: [String: Any]) -> String {
        #if os(macOS)
        guard let key = args["key"] as? String,
              let value = args["value"] as? String else { return "Error: missing key or value" }
        let service = args["service"] as? String ?? "com.grump.agent"
        guard service.hasPrefix("com.grump.") else {
            return "Error: can only store keychain items under com.grump.* service"
        }
        guard let data = value.data(using: .utf8) else { return "Error: could not encode value" }

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess {
            return "Stored '\(key)' in keychain service '\(service)'"
        }
        return "Error: Keychain store failed (status: \(status))"
        #else
        return "Error: Keychain access is only available on macOS"
        #endif
    }

    // MARK: - Calendar Events

    func executeCalendarEvents(_ args: [String: Any]) async -> String {
        #if os(macOS)
        guard let action = args["action"] as? String else { return "Error: missing action" }
        let store = EKEventStore()

        do {
            let granted = try await store.requestFullAccessToEvents()
            guard granted else { return "Error: Calendar access denied. Enable in System Settings > Privacy > Calendars." }
        } catch {
            return "Error: Calendar access request failed: \(error.localizedDescription)"
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        switch action {
        case "list":
            let startStr = args["start_date"] as? String
            let endStr = args["end_date"] as? String
            let start = startStr.flatMap { iso.date(from: $0) } ?? Date()
            let end = endStr.flatMap { iso.date(from: $0) } ?? (Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86400))
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            let events = store.events(matching: predicate)
            if events.isEmpty { return "No events found between \(start) and \(end)" }
            return events.prefix(20).map { event in
                let startFmt = DateFormatter.localizedString(from: event.startDate, dateStyle: .medium, timeStyle: .short)
                let endFmt = DateFormatter.localizedString(from: event.endDate, dateStyle: .none, timeStyle: .short)
                return "• \(event.title ?? "Untitled") — \(startFmt) to \(endFmt)\(event.notes.map { "\n  Notes: \($0)" } ?? "")"
            }.joined(separator: "\n")

        case "create":
            guard let title = args["title"] as? String else { return "Error: missing title for event creation" }
            let startStr = args["start_date"] as? String
            let endStr = args["end_date"] as? String
            guard let start = startStr.flatMap({ iso.date(from: $0) }) else { return "Error: missing or invalid start_date (use ISO 8601)" }
            let end = endStr.flatMap { iso.date(from: $0) } ?? (Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3600))
            let event = EKEvent(eventStore: store)
            event.title = title
            event.startDate = start
            event.endDate = end
            event.notes = args["notes"] as? String
            event.calendar = store.defaultCalendarForNewEvents
            try? store.save(event, span: .thisEvent)
            return "Created event '\(title)' from \(start) to \(end)"

        default:
            return "Error: unknown action '\(action)'. Use 'list' or 'create'."
        }
        #else
        return "Error: Calendar events are only available on macOS"
        #endif
    }

    // MARK: - Reminders

    func executeRemindersList(_ args: [String: Any]) async -> String {
        #if os(macOS)
        guard let action = args["action"] as? String else { return "Error: missing action" }
        let store = EKEventStore()

        do {
            let granted = try await store.requestFullAccessToReminders()
            guard granted else { return "Error: Reminders access denied. Enable in System Settings > Privacy > Reminders." }
        } catch {
            return "Error: Reminders access request failed: \(error.localizedDescription)"
        }

        switch action {
        case "list":
            let showCompleted = args["show_completed"] as? Bool ?? false
            let calendars = store.calendars(for: .reminder)
            let predicate = store.predicateForReminders(in: calendars)
            let reminders = await withCheckedContinuation { (continuation: CheckedContinuation<[EKReminder], Never>) in
                store.fetchReminders(matching: predicate) { result in
                    continuation.resume(returning: result ?? [])
                }
            }
            let filtered = showCompleted ? reminders : reminders.filter { !$0.isCompleted }
            if filtered.isEmpty { return "No \(showCompleted ? "" : "incomplete ")reminders found" }
            return filtered.prefix(30).map { r in
                let status = r.isCompleted ? "✓" : "○"
                let due = r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }.map { " (due: \(DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short)))" } ?? ""
                return "\(status) \(r.title ?? "Untitled")\(due)"
            }.joined(separator: "\n")

        case "create":
            guard let title = args["title"] as? String else { return "Error: missing title for reminder creation" }
            let reminder = EKReminder(eventStore: store)
            reminder.title = title
            reminder.calendar = store.defaultCalendarForNewReminders()
            if let dueDateStr = args["due_date"] as? String {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime]
                if let dueDate = iso.date(from: dueDateStr) {
                    reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
                }
            }
            try? store.save(reminder, commit: true)
            return "Created reminder '\(title)'"

        default:
            return "Error: unknown action '\(action)'. Use 'list' or 'create'."
        }
        #else
        return "Error: Reminders are only available on macOS"
        #endif
    }

    // MARK: - Contacts Search

    func executeContactsSearch(_ args: [String: Any]) -> String {
        #if os(macOS)
        guard let query = args["query"] as? String else { return "Error: missing query" }
        let limit = args["limit"] as? Int ?? 10
        let store = CNContactStore()
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor
        ]
        let predicate = CNContact.predicateForContacts(matchingName: query)
        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            if contacts.isEmpty { return "No contacts found matching '\(query)'" }
            return contacts.prefix(limit).map { c in
                var parts: [String] = ["• \(c.givenName) \(c.familyName)"]
                if !c.organizationName.isEmpty { parts.append("  Org: \(c.organizationName)") }
                for email in c.emailAddresses { parts.append("  Email: \(email.value as String)") }
                for phone in c.phoneNumbers { parts.append("  Phone: \(phone.value.stringValue)") }
                return parts.joined(separator: "\n")
            }.joined(separator: "\n")
        } catch {
            return "Error: Contacts search failed: \(error.localizedDescription). Enable Contacts access in System Settings > Privacy."
        }
        #else
        return "Error: Contacts search is only available on macOS"
        #endif
    }

    // MARK: - Speech Transcribe

    func executeSpeechTranscribe(_ args: [String: Any]) async -> String {
        #if os(macOS)
        guard let path = args["path"] as? String else { return "Error: missing path" }
        let resolved = resolvePath(path)
        guard FileManager.default.fileExists(atPath: resolved) else { return "Error: file not found at '\(resolved)'" }

        let locale = Locale(identifier: args["language"] as? String ?? "en-US")
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            return "Error: Speech recognizer not available for locale '\(locale.identifier)'"
        }
        guard recognizer.isAvailable else {
            return "Error: Speech recognizer not available. Check internet and privacy settings."
        }

        let url = URL(fileURLWithPath: resolved)
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        return await withCheckedContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(returning: "Error: Transcription failed: \(error.localizedDescription)")
                    return
                }
                if let result = result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
        #else
        return "Error: Speech transcription is only available on macOS"
        #endif
    }

    // MARK: - OCR Extract

    func executeOCRExtract(_ args: [String: Any]) async -> String {
        #if os(macOS)
        guard let path = args["path"] as? String else { return "Error: missing path" }
        let resolved = resolvePath(path)
        guard FileManager.default.fileExists(atPath: resolved) else { return "Error: file not found at '\(resolved)'" }

        guard let image = NSImage(contentsOfFile: resolved),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return "Error: could not load image from '\(resolved)'"
        }

        let request = VNRecognizeTextRequest()
        let level = (args["level"] as? String ?? "accurate").lowercased()
        request.recognitionLevel = level == "fast" ? .fast : .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return "Error: OCR failed: \(error.localizedDescription)"
        }

        guard let observations = request.results, !observations.isEmpty else {
            return "No text found in image"
        }

        let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        let avgConfidence = observations.compactMap { $0.topCandidates(1).first?.confidence }.reduce(0, +) / Float(observations.count)
        return "Confidence: \(Int(avgConfidence * 100))%\n\n\(text)"
        #else
        return "Error: OCR is only available on macOS"
        #endif
    }

    // MARK: - Image Classify

    func executeImageClassify(_ args: [String: Any]) async -> String {
        #if os(macOS)
        guard let path = args["path"] as? String else { return "Error: missing path" }
        let resolved = resolvePath(path)
        guard FileManager.default.fileExists(atPath: resolved) else { return "Error: file not found at '\(resolved)'" }
        let maxResults = args["max_results"] as? Int ?? 5

        guard let image = NSImage(contentsOfFile: resolved),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return "Error: could not load image from '\(resolved)'"
        }

        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return "Error: Image classification failed: \(error.localizedDescription)"
        }

        guard let observations = request.results, !observations.isEmpty else {
            return "No classifications found"
        }

        let top = observations
            .filter { $0.confidence > 0.01 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(maxResults)

        return top.map { "\($0.identifier): \(Int($0.confidence * 100))%" }.joined(separator: "\n")
        #else
        return "Error: Image classification is only available on macOS"
        #endif
    }

    // MARK: - Shortcuts Run

    func executeShortcutsRun(_ args: [String: Any]) async -> String {
        #if os(macOS)
        guard let name = args["name"] as? String else { return "Error: missing shortcut name" }
        let safeName = name.replacingOccurrences(of: "'", with: "'\\''")
        var cmd = "shortcuts run '\(safeName)'"
        if let input = args["input"] as? String {
            let safeInput = input.replacingOccurrences(of: "'", with: "'\\''")
            cmd = "echo '\(safeInput)' | shortcuts run '\(safeName)'"
        }
        return await runShellCommand(cmd, cwd: nil, timeoutSeconds: 30)
        #else
        return "Error: Shortcuts are only available on macOS"
        #endif
    }

    // MARK: - System Appearance

    func executeSystemAppearance(_ args: [String: Any]) async -> String {
        #if os(macOS)
        guard let action = args["action"] as? String else { return "Error: missing action" }
        switch action {
        case "get":
            let result = await runShellCommand("defaults read -g AppleInterfaceStyle 2>/dev/null || echo 'Light'", cwd: nil, timeoutSeconds: 5)
            let isDark = result.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "dark"
            let accent = await runShellCommand("defaults read -g AppleAccentColor 2>/dev/null || echo 'Default'", cwd: nil, timeoutSeconds: 5)
            return "Appearance: \(isDark ? "Dark" : "Light")\nAccent Color: \(accent.trimmingCharacters(in: .whitespacesAndNewlines))"
        case "set":
            if let darkMode = args["dark_mode"] as? Bool {
                if darkMode {
                    return await runShellCommand("osascript -e 'tell application \"System Events\" to tell appearance preferences to set dark mode to true'", cwd: nil, timeoutSeconds: 5)
                } else {
                    return await runShellCommand("osascript -e 'tell application \"System Events\" to tell appearance preferences to set dark mode to false'", cwd: nil, timeoutSeconds: 5)
                }
            }
            return "Error: specify dark_mode (true/false) for set action"
        default:
            return "Error: unknown action '\(action)'. Use 'get' or 'set'."
        }
        #else
        return "Error: System appearance is only available on macOS"
        #endif
    }

    // MARK: - Xcodebuild

    func executeXcodebuild(_ args: [String: Any]) async -> String {
        #if os(macOS)
        guard let action = args["action"] as? String else { return "Error: missing action" }
        var cmdParts = ["xcodebuild"]

        switch action {
        case "build", "test", "clean", "archive":
            cmdParts.append(action)
        default:
            return "Error: unknown action '\(action)'. Use 'build', 'test', 'clean', or 'archive'."
        }

        if let project = args["project"] as? String {
            cmdParts.append(contentsOf: ["-project", resolvePath(project)])
        }
        if let workspace = args["workspace"] as? String {
            cmdParts.append(contentsOf: ["-workspace", resolvePath(workspace)])
        }
        if let scheme = args["scheme"] as? String {
            cmdParts.append(contentsOf: ["-scheme", scheme])
        }
        if let destination = args["destination"] as? String {
            cmdParts.append(contentsOf: ["-destination", destination])
        }
        let config = args["configuration"] as? String ?? "Debug"
        cmdParts.append(contentsOf: ["-configuration", config])

        let cmd = cmdParts.map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " ")
        return await runShellCommand("\(cmd) 2>&1 | tail -50", cwd: nil, timeoutSeconds: 300)
        #else
        return "Error: xcodebuild is only available on macOS"
        #endif
    }

    // MARK: - xcrun simctl

    func executeXcrunSimctl(_ args: [String: Any]) async -> String {
        #if os(macOS)
        guard let action = args["action"] as? String else { return "Error: missing action" }
        switch action {
        case "list":
            return await runShellCommand("xcrun simctl list devices available --json 2>/dev/null | head -100", cwd: nil, timeoutSeconds: 10)
        case "boot":
            guard let deviceId = args["device_id"] as? String else { return "Error: missing device_id" }
            let safeId = deviceId.replacingOccurrences(of: "'", with: "'\\''")
            return await runShellCommand("xcrun simctl boot '\(safeId)' 2>&1", cwd: nil, timeoutSeconds: 15)
        case "shutdown":
            guard let deviceId = args["device_id"] as? String else { return "Error: missing device_id" }
            let safeId = deviceId.replacingOccurrences(of: "'", with: "'\\''")
            return await runShellCommand("xcrun simctl shutdown '\(safeId)' 2>&1", cwd: nil, timeoutSeconds: 10)
        case "install":
            guard let deviceId = args["device_id"] as? String,
                  let appPath = args["app_path"] as? String else { return "Error: missing device_id or app_path" }
            let safeId = deviceId.replacingOccurrences(of: "'", with: "'\\''")
            let safePath = resolvePath(appPath).replacingOccurrences(of: "'", with: "'\\''")
            return await runShellCommand("xcrun simctl install '\(safeId)' '\(safePath)' 2>&1", cwd: nil, timeoutSeconds: 30)
        case "screenshot":
            guard let deviceId = args["device_id"] as? String else { return "Error: missing device_id" }
            let output = args["output_path"] as? String ?? "/tmp/simulator_screenshot.png"
            let safeId = deviceId.replacingOccurrences(of: "'", with: "'\\''")
            let safeOutput = resolvePath(output).replacingOccurrences(of: "'", with: "'\\''")
            return await runShellCommand("xcrun simctl io '\(safeId)' screenshot '\(safeOutput)' 2>&1 && echo 'Screenshot saved to \(safeOutput)'", cwd: nil, timeoutSeconds: 10)
        case "delete":
            guard let deviceId = args["device_id"] as? String else { return "Error: missing device_id" }
            let safeId = deviceId.replacingOccurrences(of: "'", with: "'\\''")
            return await runShellCommand("xcrun simctl delete '\(safeId)' 2>&1", cwd: nil, timeoutSeconds: 10)
        default:
            return "Error: unknown action '\(action)'. Use 'list', 'boot', 'shutdown', 'install', 'screenshot', or 'delete'."
        }
        #else
        return "Error: xcrun simctl is only available on macOS"
        #endif
    }

    // MARK: - Swift Format

    func executeSwiftFormat(_ args: [String: Any]) async -> String {
        #if os(macOS)
        guard let path = args["path"] as? String else { return "Error: missing path" }
        let resolved = resolvePath(path)
        let inPlace = args["in_place"] as? Bool ?? false
        var cmd = "swift-format"
        if inPlace { cmd += " --in-place" }
        cmd += " '\(resolved.replacingOccurrences(of: "'", with: "'\\''"))'"
        if let config = args["config"] as? String {
            cmd += " --configuration '\(resolvePath(config).replacingOccurrences(of: "'", with: "'\\''"))'"
        }
        let result = await runShellCommand("\(cmd) 2>&1", cwd: nil, timeoutSeconds: 30)
        if inPlace && result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Formatted '\(resolved)' in place"
        }
        return result.isEmpty ? "No output (file may already be formatted)" : result
        #else
        return "Error: swift-format is only available on macOS"
        #endif
    }

    // MARK: - Swift Lint

    func executeSwiftLint(_ args: [String: Any]) async -> String {
        #if os(macOS)
        guard let path = args["path"] as? String else { return "Error: missing path" }
        let resolved = resolvePath(path)
        let fix = args["fix"] as? Bool ?? false
        var cmd = fix ? "swiftlint --fix" : "swiftlint lint"
        cmd += " --path '\(resolved.replacingOccurrences(of: "'", with: "'\\''"))'"
        if let config = args["config"] as? String {
            cmd += " --config '\(resolvePath(config).replacingOccurrences(of: "'", with: "'\\''"))'"
        }
        return await runShellCommand("\(cmd) 2>&1 | head -50", cwd: nil, timeoutSeconds: 30)
        #else
        return "Error: swiftlint is only available on macOS"
        #endif
    }

    // MARK: - Swift Package

    func executeSwiftPackage(_ args: [String: Any]) async -> String {
        #if os(macOS)
        guard let action = args["action"] as? String else { return "Error: missing action" }
        let dir = (args["directory"] as? String).map { resolvePath($0) } ?? (workingDirectory.isEmpty ? "." : workingDirectory)
        let validActions = ["resolve", "update", "show-dependencies", "generate-xcodeproj", "dump-package", "init", "reset"]
        guard validActions.contains(action) else {
            return "Error: unknown action '\(action)'. Use: \(validActions.joined(separator: ", "))"
        }
        return await runShellCommand("cd '\(dir.replacingOccurrences(of: "'", with: "'\\''"))' && swift package \(action) 2>&1 | tail -40", cwd: dir, timeoutSeconds: 120)
        #else
        return "Error: Swift Package Manager is only available on macOS"
        #endif
    }

    // MARK: - PDF Extract

    func executePdfExtract(_ args: [String: Any]) -> String {
        #if os(macOS)
        guard let path = args["path"] as? String else { return "Error: missing path" }
        let resolved = resolvePath(path)
        guard let doc = PDFDocument(url: URL(fileURLWithPath: resolved)) else {
            return "Error: could not open PDF at '\(resolved)'"
        }
        let startPage = max(1, args["start_page"] as? Int ?? 1)
        let endPage = min(doc.pageCount, args["end_page"] as? Int ?? doc.pageCount)
        var text = ""
        for i in (startPage - 1)..<endPage {
            if let page = doc.page(at: i), let pageText = page.string {
                text += "--- Page \(i + 1) ---\n\(pageText)\n\n"
            }
        }
        return text.isEmpty ? "No text found in pages \(startPage)-\(endPage)" : "PDF: \(resolved) (\(doc.pageCount) pages)\n\n\(text)"
        #else
        return "Error: PDF extraction is only available on macOS"
        #endif
    }

    // MARK: - TTS Speak

    func executeTtsSpeak(_ args: [String: Any]) async -> String {
        #if os(macOS)
        guard let text = args["text"] as? String else { return "Error: missing text" }
        let rate = args["rate"] as? Float ?? 0.5

        if let outputPath = args["output_path"] as? String {
            let resolved = resolvePath(outputPath)
            let safeText = text.replacingOccurrences(of: "'", with: "'\\''")
            return await runShellCommand("say '\(safeText)' -o '\(resolved.replacingOccurrences(of: "'", with: "'\\''"))' --data-format=LEF32@22050 2>&1 && echo 'Audio saved to \(resolved)'", cwd: nil, timeoutSeconds: 30)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        if let voiceId = args["voice"] as? String {
            utterance.voice = AVSpeechSynthesisVoice(identifier: voiceId)
        }
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.speak(utterance)
        return "Speaking: \"\(text.prefix(80))\(text.count > 80 ? "..." : "")\""
        #else
        return "Error: TTS is only available on macOS"
        #endif
    }

    // MARK: - QR Generate

    func executeQrGenerate(_ args: [String: Any]) -> String {
        #if os(macOS)
        guard let content = args["content"] as? String,
              let outputPath = args["output_path"] as? String else { return "Error: missing content or output_path" }
        let size = args["size"] as? Int ?? 512
        let resolved = resolvePath(outputPath)

        guard let data = content.data(using: .utf8) else { return "Error: could not encode content" }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return "Error: QR code generator not available" }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return "Error: could not generate QR code" }
        let scale = CGFloat(size) / ciImage.extent.width
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return "Error: could not render QR code image"
        }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return "Error: could not convert QR code to PNG"
        }

        do {
            try pngData.write(to: URL(fileURLWithPath: resolved))
            return "QR code saved to \(resolved) (\(size)x\(size)px)"
        } catch {
            return "Error writing QR code: \(error.localizedDescription)"
        }
        #else
        return "Error: QR code generation is only available on macOS"
        #endif
    }

    // MARK: - WebSocket Send

    func executeWebsocketSend(_ args: [String: Any]) async -> String {
        guard let urlStr = args["url"] as? String,
              let message = args["message"] as? String else { return "Error: missing url or message" }
        guard let url = URL(string: urlStr) else { return "Error: invalid URL '\(urlStr)'" }
        let timeout = args["timeout"] as? Int ?? 10

        let session = URLSession(configuration: .default)
        let wsTask = session.webSocketTask(with: url)
        wsTask.resume()

        do {
            try await wsTask.send(.string(message))
            let response = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    let msg = try await wsTask.receive()
                    switch msg {
                    case .string(let text): return text
                    case .data(let data): return String(data: data, encoding: .utf8) ?? "<binary data: \(data.count) bytes>"
                    @unknown default: return "<unknown message type>"
                    }
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    throw URLError(.timedOut)
                }
                guard let result = try await group.next() else {
                    group.cancelAll()
                    return "Error: WebSocket task group returned nil"
                }
                group.cancelAll()
                return result
            }
            wsTask.cancel(with: .goingAway, reason: nil)
            return response
        } catch {
            wsTask.cancel(with: .goingAway, reason: nil)
            return "Error: WebSocket failed: \(error.localizedDescription)"
        }
    }

    // MARK: - GraphQL Query

    func executeGraphqlQuery(_ args: [String: Any]) async -> String {
        guard let urlStr = args["url"] as? String,
              let query = args["query"] as? String else { return "Error: missing url or query" }
        guard let url = URL(string: urlStr) else { return "Error: invalid URL '\(urlStr)'" }

        var body: [String: Any] = ["query": query]
        if let variables = args["variables"] as? String,
           let varsData = variables.data(using: .utf8),
           let vars = try? JSONSerialization.jsonObject(with: varsData) {
            body["variables"] = vars
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let headersStr = args["headers"] as? String,
           let headersData = headersStr.data(using: .utf8),
           let headers = try? JSONSerialization.jsonObject(with: headersData) as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return "Error: could not serialize GraphQL request body"
        }
        request.httpBody = bodyData
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return "Error: HTTP \(http.statusCode)\n\(String(data: data, encoding: .utf8) ?? "")"
            }
            if let pretty = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: pretty, options: .prettyPrinted) {
                return String(data: prettyData, encoding: .utf8) ?? String(data: data, encoding: .utf8) ?? ""
            }
            return String(data: data, encoding: .utf8) ?? "<binary response>"
        } catch {
            return "Error: GraphQL request failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Bonjour Discover

    func executeBonjourDiscover(_ args: [String: Any]) async -> String {
        #if os(macOS)
        guard let serviceType = args["service_type"] as? String else { return "Error: missing service_type" }
        let domain = args["domain"] as? String ?? "local."
        let timeout = args["timeout"] as? Int ?? 5

        return await withCheckedContinuation { continuation in
            let delegate = BonjourDiscoveryDelegate()
            let browser = NetServiceBrowser()
            browser.delegate = delegate

            DispatchQueue.global().async { [browser, delegate] in
                browser.searchForServices(ofType: serviceType, inDomain: domain)
                Thread.sleep(forTimeInterval: Double(timeout))
                browser.stop()

                let services = delegate.discoveredServices
                if services.isEmpty {
                    continuation.resume(returning: "No services found for type '\(serviceType)' in domain '\(domain)'")
                } else {
                    let result = services.map { "• \($0.name) (\($0.type)) — \($0.domain)" }.joined(separator: "\n")
                    continuation.resume(returning: "Found \(services.count) service(s):\n\(result)")
                }
            }
        }
        #else
        return "Error: Bonjour discovery is only available on macOS"
        #endif
    }
}

// MARK: - Bonjour Discovery Delegate

#if os(macOS)
private final class BonjourDiscoveryDelegate: NSObject, NetServiceBrowserDelegate, @unchecked Sendable {
    var discoveredServices: [NetService] = []

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        discoveredServices.append(service)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        // Discovery error — ignore silently
    }
}
#endif
