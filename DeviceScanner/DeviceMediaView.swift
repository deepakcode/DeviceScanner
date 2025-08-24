//
//  DeviceMediaView.swift
//  DeviceScanner
//
//  Updated: fixes Int64? vs UInt64? size-formatter mismatch and ViewBuilder inference.
//

import SwiftUI
import AppKit
import ImageCaptureCore

// MARK: - Abstraction to avoid subclassing final IOSMediaLibrary in previews

protocol IOSMediaLibraryProvider: ObservableObject {
    func allItems() -> [IOSMediaItem]
    func openFile(at index: Int, completion: @escaping (URL?) -> Void)
}

extension IOSMediaLibrary: IOSMediaLibraryProvider {}

// MARK: - View

struct DeviceMediaView<L: IOSMediaLibraryProvider>: View {
    @ObservedObject var library: L

    @State private var gridColumns: [GridItem] = [GridItem(.adaptive(minimum: 140), spacing: 12)]
    @State private var isOpening: Bool = false
    @State private var openURL: URL?

    var body: some View {
        Group {
            if library.allItems().isEmpty {
                emptyState
            } else {
                mediaGrid
            }
        }
        .sheet(isPresented: $isOpening, onDismiss: { openURL = nil }) {
            Group {
                if let openURL {
                    FilePreviewView(fileURL: openURL)
                } else {
                    VStack {
                        ProgressView()
                        Text("Preparing preview...")
                            .padding(.top, 8)
                    }
                    .frame(width: 400, height: 200)
                }
            }
        }
        .navigationTitle("Device Media")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh contents")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "iphone.rear.camera")
                .font(.system(size: 48))
            Text("No media found")
                .font(.headline)
            Text("Connect a device or unlock it to allow access.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Grid

    private var mediaGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                let items = library.allItems()

                // Use enumerated to avoid index type pitfalls
                ForEach(Array(items.enumerated()), id: \.offset) { pair in
                    let idx = pair.offset
                    let item = pair.element

                    mediaCell(item)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { open(index: idx) }
                        .contextMenu {
                            Button("Open") { open(index: idx) }
                            if let sizeLabel = byteSizeString(item.byteSize) {
                                Text("Size: \(sizeLabel)")
                            }
                            if let created = item.created {
                                Text("Created: \(dateString(created))")
                            }
                        }
                        .accessibilityLabel(item.name)
                }
            }
            .padding(12)
        }
    }

    // MARK: - Cell

    @ViewBuilder
    private func mediaCell(_ item: IOSMediaItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnailView(for: item)
                .frame(width: 120, height: 120)
                .clipped()
                .cornerRadius(8)

            Text(item.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)

            // Build a single meta string to avoid mixed view types in the builder
            let meta: String? = {
                if let w = item.pixelWidth, let h = item.pixelHeight, w > 0, h > 0 {
                    return "\(w) × \(h)"
                } else if let size = byteSizeString(item.byteSize) {
                    return size
                } else {
                    return nil
                }
            }()

            if let meta {
                Text(meta)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.secondary.opacity(0.15))
        )
    }

    @ViewBuilder
    private func thumbnailView(for item: IOSMediaItem) -> some View {
        Group {
            if let image = item.thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.gray.opacity(0.08))
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Loading…")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func open(index: Int) {
        isOpening = false
        openURL = nil

        library.openFile(at: index) { url in
            DispatchQueue.main.async {
                if let url {
                    self.openURL = url
                    self.isOpening = true
                }
            }
        }
    }

    private func refresh() {
        // Hook in explicit refresh if you add it to IOSMediaLibraryProvider later.
    }

    // MARK: - Helpers

    // Accept Int64? because many file-size APIs use signed Int64
    private func byteSizeString(_ bytes: Int64?) -> String? {
        guard let bytes = bytes, bytes > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func dateString(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}

// MARK: - Simple File Preview (macOS)

private struct FilePreviewView: View {
    let fileURL: URL

    var body: some View {
        VStack(spacing: 12) {
            Text(fileURL.lastPathComponent)
                .font(.headline)
                .lineLimit(2)
                .truncationMode(.middle)

            Group {
                if let image = NSImage(contentsOf: fileURL) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(minWidth: 360, minHeight: 240)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "doc")
                            .font(.system(size: 48))
                        Text("Preview not available")
                            .foregroundColor(.secondary)
                        Text(fileURL.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                    }
                    .frame(minWidth: 360, minHeight: 240)
                }
            }

            HStack {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
                Spacer()
                Button("Open with Default App") {
                    NSWorkspace.shared.open(fileURL)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 320)
    }
}

// MARK: - Preview

#if DEBUG
private final class PreviewLibrary: IOSMediaLibraryProvider {
    @Published var items: [IOSMediaItem] = [
        IOSMediaItem(name: "IMG_0001.JPG", byteSize: 1_234_567, created: Date(), pixelWidth: 4032, pixelHeight: 3024, kind: .photo, thumbnail: nil),
        IOSMediaItem(name: "IMG_0002.HEIC", byteSize: 1_834_567, created: Date(), pixelWidth: 4032, pixelHeight: 3024, kind: .photo, thumbnail: nil),
        IOSMediaItem(name: "VID_0003.MOV", byteSize: 12_834_567, created: Date(), pixelWidth: 1920, pixelHeight: 1080, kind: .video, thumbnail: nil)
    ]

    func allItems() -> [IOSMediaItem] { items }

    func openFile(at index: Int, completion: @escaping (URL?) -> Void) {
        completion(nil) // preview only
    }
}

struct DeviceMediaView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceMediaView(library: PreviewLibrary())
            .frame(width: 800, height: 600)
    }
}
#endif

