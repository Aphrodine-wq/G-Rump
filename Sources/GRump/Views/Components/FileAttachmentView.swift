import SwiftUI

// MARK: - File Attachment View

struct FileAttachmentView: View {
    let fileURL: URL
    let onRemove: () -> Void
    @EnvironmentObject var themeManager: ThemeManager

    private var fileName: String {
        fileURL.lastPathComponent
    }

    private var fileExtension: String {
        fileURL.pathExtension.lowercased()
    }

    private var fileSize: String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let size = attributes[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
        } catch {
            return "Unknown"
        }
        return "Unknown"
    }

    private var fileIcon: String {
        switch fileExtension {
        case "txt", "md", "markdown": return "doc.text"
        case "pdf": return "doc.pdf"
        case "doc", "docx": return "doc.word"
        case "xls", "xlsx": return "doc.chart.bar"
        case "ppt", "pptx": return "doc.chart.bar.fill"
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp": return "photo"
        case "mp4", "mov", "avi", "mkv": return "video"
        case "mp3", "wav", "m4a", "flac": return "music.note"
        case "zip", "rar", "7z", "tar", "gz": return "doc.zipper"
        case "swift", "m", "h", "c", "cpp", "py", "js", "ts", "html", "css": return "chevron.left.forwardslash.chevron.right"
        case "json", "xml", "yaml", "yml": return "doc.text.magnifyingglass"
        default: return "doc"
        }
    }

    private var fileType: FileType {
        if isImageFile { return .image }
        if isVideoFile { return .video }
        if isAudioFile { return .audio }
        if isCodeFile { return .code }
        if isDocumentFile { return .document }
        if isArchiveFile { return .archive }
        return .other
    }

    private var isImageFile: Bool {
        ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp"].contains(fileExtension)
    }

    private var isVideoFile: Bool {
        ["mp4", "mov", "avi", "mkv"].contains(fileExtension)
    }

    private var isAudioFile: Bool {
        ["mp3", "wav", "m4a", "flac"].contains(fileExtension)
    }

    private var isCodeFile: Bool {
        ["swift", "m", "h", "c", "cpp", "py", "js", "ts", "html", "css", "rs", "go", "java", "kt"].contains(fileExtension)
    }

    private var isDocumentFile: Bool {
        ["txt", "md", "markdown", "pdf", "doc", "docx", "pages"].contains(fileExtension)
    }

    private var isArchiveFile: Bool {
        ["zip", "rar", "7z", "tar", "gz"].contains(fileExtension)
    }

    private enum FileType {
        case image, video, audio, code, document, archive, other
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // File icon with preview
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(fileTypeBackgroundColor)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Group {
                            if isImageFile {
                                AsyncImage(url: fileURL) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                }
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
                            } else {
                                Image(systemName: fileIcon)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(fileTypeForegroundColor)
                            }
                        }
                    )
            }

            // File info
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(fileName)
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(fileSize)
                    .font(Typography.micro)
                    .foregroundColor(.textMuted)
            }

            Spacer()

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.textMuted)
                    .background(Circle().fill(themeManager.palette.bgElevated))
            }
            .buttonStyle(.plain)
            .help("Remove attachment")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(themeManager.palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin)
                )
        )
        .scaleEffect(1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: fileURL)
    }

    private var fileTypeBackgroundColor: Color {
        switch fileType {
        case .image: return themeManager.palette.effectiveAccent.opacity(0.1)
        case .video: return Color.red.opacity(0.1)
        case .audio: return Color.orange.opacity(0.1)
        case .code: return Color.green.opacity(0.1)
        case .document: return Color.blue.opacity(0.1)
        case .archive: return Color.purple.opacity(0.1)
        case .other: return themeManager.palette.bgElevated
        }
    }

    private var fileTypeForegroundColor: Color {
        switch fileType {
        case .image: return themeManager.palette.effectiveAccent
        case .video: return Color.red
        case .audio: return Color.orange
        case .code: return Color.green
        case .document: return Color.blue
        case .archive: return Color.purple
        case .other: return .textMuted
        }
    }
}

// MARK: - Async Image for File Previews

struct AsyncImage<Content>: View where Content: View {
    private let url: URL
    private let content: (Image) -> Content

    @State private var image: Image?
    @State private var isLoading = true

    init(url: URL, @ViewBuilder content: @escaping (Image) -> Content) {
        self.url = url
        self.content = content
    }

    var body: some View {
        Group {
            if let image = image {
                content(image)
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.textMuted)
            }
        }
        .onAppear {
            Task {
                await loadImage()
            }
        }
    }

    @MainActor
    private func loadImage() async {
        isLoading = true

        do {
            let data = try Data(contentsOf: url)
            #if os(macOS)
            if let nsImage = NSImage(data: data) {
                self.image = Image(nsImage: nsImage)
            }
            #else
            if let uiImage = UIImage(data: data) {
                self.image = Image(uiImage: uiImage)
            }
            #endif
        } catch {
            GRumpLogger.general.error("Failed to load image: \(error.localizedDescription)")
        }

        isLoading = false
    }
}
