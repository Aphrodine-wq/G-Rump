import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Loads and displays images from URLs in markdown content.
/// Uses manual URLSession loading to avoid AsyncImage overload resolution issues.
struct MarkdownImageLoader: View {
    @EnvironmentObject var themeManager: ThemeManager
    let url: URL
    let alt: String

    @State private var loadedImage: PlatformImage?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let platformImage = loadedImage {
                #if os(macOS)
                SwiftUI.Image(nsImage: platformImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 600, maxHeight: 400)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .stroke(themeManager.palette.borderSubtle, lineWidth: Border.thin)
                    )
                #else
                SwiftUI.Image(uiImage: platformImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 600, maxHeight: 400)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .stroke(themeManager.palette.borderSubtle, lineWidth: Border.thin)
                    )
                #endif
            } else if loadFailed {
                HStack(spacing: Spacing.md) {
                    SwiftUI.Image(systemName: "photo.badge.exclamationmark")
                        .foregroundColor(themeManager.palette.textMuted)
                    Text(alt.isEmpty ? "Failed to load image" : alt)
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .padding(Spacing.lg)
                .background(themeManager.palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            } else {
                HStack(spacing: Spacing.md) {
                    ProgressView()
                        .controlSize(.small)
                    Text(alt.isEmpty ? "Loading image..." : alt)
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .padding(Spacing.lg)
            }
        }
        .task {
            await loadImage()
        }
    }

    private func loadImage() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            #if os(macOS)
            if let img = NSImage(data: data) {
                loadedImage = img
            } else {
                loadFailed = true
            }
            #else
            if let img = UIImage(data: data) {
                loadedImage = img
            } else {
                loadFailed = true
            }
            #endif
        } catch {
            loadFailed = true
        }
    }
}

#if os(macOS)
private typealias PlatformImage = NSImage
#else
private typealias PlatformImage = UIImage
#endif
