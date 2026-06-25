import SwiftUI
#if os(macOS)
import AppKit
import ScreenCaptureKit
#else
import UIKit
#endif

struct ChatInputView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var text: String
    var isLoading: Bool
    var onSend: () -> Void
    var focus: FocusState<Bool>.Binding
    var onStop: (() -> Void)?
    var onFileAttached: (([URL]) -> Void)?

    @AppStorage("ReturnToSend") private var returnToSend = false
    @AppStorage("HasSentFirstMessage") private var hasSentFirstMessage = false
    private let minHeight: CGFloat = 28
    private let maxHeight: CGFloat = 48
    @State private var attachedFiles: [URL] = []
    @State private var isDragOver: Bool = false
    @State private var showAttachPopover = false
    #if os(macOS)
    @StateObject private var voiceService = VoiceInputService()
    #endif

    var body: some View {
        VStack(spacing: Spacing.md) {
            // Attached files display
            if !attachedFiles.isEmpty {
                attachedFilesView
            }

            // Floating minimal input bar
            HStack(spacing: Spacing.md) {
                // Plus button for attachments
                #if os(macOS)
                Button(action: { showAttachPopover.toggle() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(themeManager.palette.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(themeManager.palette.bgElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showAttachPopover, arrowEdge: .top) {
                    attachmentPopoverContent
                }
                #endif

                // Text input
                #if os(macOS)
                NativeTextInputContainer(
                    text: $text,
                    font: NSFont.systemFont(ofSize: 14),
                    textColor: NSColor(themeManager.palette.textPrimary),
                    placeholderText: "Ask anything...",
                    placeholderColor: NSColor(themeManager.palette.textMuted),
                    minHeight: minHeight,
                    maxHeight: maxHeight,
                    isFirstResponder: focus.wrappedValue,
                    onReturnKey: { event in
                        if returnToSend {
                            if event.modifierFlags.contains(.shift) {
                                return false // Let newline through
                            }
                            if canSend { sendAndTrack() }
                            return true
                        } else {
                            if event.modifierFlags.contains(.command) {
                                if canSend { sendAndTrack() }
                                return true
                            }
                            return false
                        }
                    },
                    onDrop: { providers in
                        handleFileDropProviders(providers: providers)
                        return true
                    }
                )
                .frame(maxWidth: .infinity)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        focus.wrappedValue = true
                    }
                }
                .onChange(of: isLoading) { _, newLoading in
                    if !newLoading {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            focus.wrappedValue = true
                        }
                    }
                }
                #else
                // iOS: Use standard TextEditor
                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text("Ask anything...")
                            .foregroundColor(themeManager.palette.textMuted)
                            .font(Typography.body)
                            .padding(.horizontal, Spacing.md)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $text)
                        .font(Typography.body)
                        .foregroundColor(themeManager.palette.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.sm)
                        .frame(minHeight: minHeight, maxHeight: maxHeight)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        .focused(focus)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                focus.wrappedValue = true
                            }
                        }
                        .onChange(of: isLoading) { _, newLoading in
                            if !newLoading {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    focus.wrappedValue = true
                                }
                            }
                        }
                }
                .contentShape(Rectangle())
                #endif

                // Mic button for voice
                #if os(macOS)
                Button(action: { voiceService.toggleRecording() }) {
                    Image(systemName: voiceService.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(voiceService.isRecording ? Color(red: 1.0, green: 0.3, blue: 0.3) : themeManager.palette.textMuted)
                        .frame(width: 32, height: 32)
                        .background(voiceService.isRecording ? Color(red: 1.0, green: 0.3, blue: 0.3).opacity(0.15) : Color.clear)
                        .clipShape(Circle())
                        .animation(.easeInOut(duration: 0.2), value: voiceService.isRecording)
                }
                .buttonStyle(.plain)
                .help(voiceService.isRecording ? "Stop recording" : "Voice input")
                .onChange(of: voiceService.transcribedText) { _, newText in
                    if !newText.isEmpty {
                        text = newText
                    }
                }
                .onChange(of: voiceService.isRecording) { _, recording in
                    if !recording && !voiceService.transcribedText.isEmpty {
                        text = voiceService.transcribedText
                        focus.wrappedValue = true
                    }
                }
                #endif

                // Send/Stop button
                sendStopButton
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(themeManager.palette.bgInput)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                            .stroke(focus.wrappedValue ? themeManager.palette.effectiveAccent.opacity(0.5) : themeManager.palette.borderSubtle, lineWidth: focus.wrappedValue ? 2 : 1)
                    )
            )
            .shadow(color: themeManager.palette.bgDark.opacity(0.3), radius: 8, y: 4)
            .animation(.easeInOut(duration: Anim.standard), value: focus.wrappedValue)

            // Send hint (hidden after first message)
            if !hasSentFirstMessage {
                Text(returnToSend ? "Return to send  ·  ⇧ Return for new line" : "⌘ Return to send  ·  Return for new line")
                    .font(Typography.micro)
                    .foregroundColor(themeManager.palette.textMuted.opacity(0.6))
            }
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.bottom, Spacing.xl)
    }

    // MARK: - Attachment Popover

    #if os(macOS)
    private var attachmentPopoverContent: some View {
        HStack(spacing: Spacing.xxl) {
            attachmentOption(
                icon: "camera.viewfinder",
                label: "Screenshot",
                color: Color(red: 1.0, green: 0.6, blue: 0.2)
            ) {
                showAttachPopover = false
                captureScreenshot()
            }
            attachmentOption(
                icon: "doc",
                label: "File",
                color: Color(red: 0.2, green: 0.7, blue: 1.0)
            ) {
                showAttachPopover = false
                openFilePicker()
            }
            attachmentOption(
                icon: "photo",
                label: "Image",
                color: Color(red: 0.85, green: 0.3, blue: 0.9)
            ) {
                showAttachPopover = false
                openImagePicker()
            }
            if ContinuityScannerService.shared.isScanningAvailable {
                attachmentOption(
                    icon: "doc.viewfinder",
                    label: "Scan",
                    color: Color(red: 0.2, green: 0.8, blue: 0.6)
                ) {
                    showAttachPopover = false
                    scanDocument()
                }
            }
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.vertical, Spacing.xxl)
    }

    private func attachmentOption(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(color)
                }
                Text(label)
                    .font(Typography.captionSmallMedium)
                    .foregroundColor(themeManager.palette.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func captureScreenshot() {
        Task {
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let filename = "screenshot_\(Int(Date().timeIntervalSince1970)).png"
                let fileURL = tempDir.appendingPathComponent(filename)

                if let cgImage = CGDisplayCreateImage(CGMainDisplayID()) {
                    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
                    if let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                        try pngData.write(to: fileURL)
                        await MainActor.run {
                            attachedFiles.append(fileURL)
                            onFileAttached?(attachedFiles)
                        }
                    }
                }
            } catch {
                GRumpLogger.capture.error("Screenshot failed: \(error.localizedDescription)")
            }
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            if response == .OK {
                attachedFiles.append(contentsOf: panel.urls)
                onFileAttached?(attachedFiles)
            }
        }
    }

    private func openImagePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .png, .jpeg, .gif, .webP, .svg, .heic]
        panel.begin { response in
            if response == .OK {
                attachedFiles.append(contentsOf: panel.urls)
                onFileAttached?(attachedFiles)
            }
        }
    }

    private func scanDocument() {
        Task {
            do {
                if let scanned = try await ContinuityScannerService.shared.startDocumentScanning() {
                    let tempDir = FileManager.default.temporaryDirectory
                    let filename = "scan_\(Int(Date().timeIntervalSince1970)).png"
                    let fileURL = tempDir.appendingPathComponent(filename)
                    let bitmapRep = NSBitmapImageRep(cgImage: scanned.image)
                    if let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                        try pngData.write(to: fileURL)
                        await MainActor.run {
                            attachedFiles.append(fileURL)
                            onFileAttached?(attachedFiles)
                        }
                    }
                }
            } catch {
                GRumpLogger.capture.error("Document scan failed: \(error.localizedDescription)")
            }
        }
    }

    #endif

    // MARK: - Send / Stop Button

    @ViewBuilder
    private var sendStopButton: some View {
        if isLoading {
            Button(action: {
                HapticHelper.impact()
                onStop?()
            }) {
                Image(systemName: "square.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                    .frame(width: 32, height: 32)
                    .background(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop generation")
        } else {
            Button(action: {
                HapticHelper.impact()
                sendAndTrack()
            }) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(canSend ? .white : themeManager.palette.textMuted)
                    .frame(width: 32, height: 32)
                    .background(
                        canSend
                            ? themeManager.palette.effectiveAccent
                            : themeManager.palette.bgElevated
                    )
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send message")
        }
    }

    private func sendAndTrack() {
        hasSentFirstMessage = true
        onSend()
        focus.wrappedValue = true
    }

    // MARK: - Attached Files View

    @ViewBuilder
    private var attachedFilesView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(Array(attachedFiles.enumerated()), id: \.offset) { _, fileURL in
                    FileAttachmentView(
                        fileURL: fileURL,
                        onRemove: { removeAttachment(fileURL) }
                    )
                }
            }
            .padding(.horizontal, Spacing.xxl)
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    // MARK: - File Handling

    private func handleFileDrop(providers: [NSItemProvider], location: CGPoint) {
        Task {
            await handleFiles(from: providers)
        }
    }

    private func handleFileDropProviders(providers: [NSItemProvider]) {
        Task {
            await handleFiles(from: providers)
        }
    }

    @MainActor
    private func handleFiles(from providers: [NSItemProvider]) async {
        var newFiles: [URL] = []

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                do {
                    let url: URL = try await withCheckedThrowingContinuation { continuation in
                        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                            if let error = error {
                                continuation.resume(throwing: error)
                            } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                continuation.resume(returning: url)
                            } else if let url = item as? URL {
                                continuation.resume(returning: url)
                            } else {
                                continuation.resume(throwing: NSError(domain: "FileDropError", code: -1))
                            }
                        }
                    }
                    newFiles.append(url)
                } catch {
                    GRumpLogger.capture.error("Failed to load file URL: \(error.localizedDescription)")
                }
            }
        }

        attachedFiles.append(contentsOf: newFiles)
        onFileAttached?(attachedFiles)
    }

    private func removeAttachment(_ url: URL) {
        attachedFiles.removeAll { $0 == url }
        onFileAttached?(attachedFiles)
    }
}
