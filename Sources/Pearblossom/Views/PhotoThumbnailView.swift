import SwiftUI

/// Displays a thumbnail for a photo. Prefers a pre-generated thumbnail if available,
/// otherwise loads and resizes the source image on a background queue.
struct PhotoThumbnailView: View {

    let sourcePath: String
    let thumbnailPath: String?

    var body: some View {
        Group {
            if let thumbPath = thumbnailPath, let image = NSImage(contentsOfFile: thumbPath) {
                Image(nsImage: image)
                    .resizable()
            } else {
                AsyncSourceThumbnail(path: sourcePath)
            }
        }
    }
}

// MARK: - Async Source Thumbnail

/// Fallback: loads and resizes the source image on a background queue.
private struct AsyncSourceThumbnail: View {

    let path: String

    @State private var thumbnail: NSImage? = nil
    @State private var loadFailed: Bool = false

    var body: some View {
        Group {
            if let image = thumbnail {
                Image(nsImage: image)
                    .resizable()
            } else if loadFailed {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        Image(systemName: "photo.badge.exclamationmark")
                            .foregroundColor(.secondary)
                    )
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.7)
                    )
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        guard thumbnail == nil else { return }

        let url = URL(fileURLWithPath: path)
        let size = CGSize(width: 120, height: 120)

        DispatchQueue.global(qos: .userInitiated).async {
            guard let image = NSImage(contentsOf: url) else {
                DispatchQueue.main.async { loadFailed = true }
                return
            }

            let thumb = image.resized(to: size)

            DispatchQueue.main.async {
                self.thumbnail = thumb
            }
        }
    }
}

// MARK: - NSImage Resize

private extension NSImage {
    func resized(to targetSize: CGSize) -> NSImage {
        let scale = min(
            targetSize.width / size.width,
            targetSize.height / size.height,
            1.0  // never upscale
        )
        let newSize = NSSize(
            width: size.width * scale,
            height: size.height * scale
        )
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        draw(in: NSRect(origin: .zero, size: newSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy, fraction: 1.0)
        resized.unlockFocus()
        return resized
    }
}
