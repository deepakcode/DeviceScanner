//  DeviceMediaView.swift
//  DeviceScanner
//
//  Updated: folders-first navigation, photo/video filter, and thumbnail flicker fixes.
//

import SwiftUI
import AppKit
import ImageCaptureCore

// MARK: - Abstraction for previews and testing
protocol IOSMediaLibraryProvider: ObservableObject {
    // Legacy API (kept for compatibility)
    func allItems() -> [IOSMediaItem]
    func openFile(at index: Int, completion: @escaping (URL?) -> Void)

    // New folder-first API
    func folders() -> [IOSMediaFolder]
    func items(in folderID: IOSFolderID, filter: MediaKind?) -> [IOSMediaItem]
    func displayName() -> String
}

extension IOSMediaLibrary: IOSMediaLibraryProvider {}

// MARK: - View

struct DeviceMediaView<L: IOSMediaLibraryProvider>: View {
    @ObservedObject var library: L

    @State private var gridColumns: [GridItem] = [GridItem(.adaptive(minimum: 140), spacing: 12)]
    @State private var isOpening: Bool = false
    @State private var openURL: URL?

    // Navigation State
    @State private var selectedFolder: IOSMediaFolder? = nil
    @State private var filter: MediaKind? = nil // nil = All

    var body: some View {
        Group {
            if let folder = selectedFolder {
                // Media inside selected folder
                mediaList(in: folder)
            } else {
                // Top-level Folder Grid
                folderGrid
            }
        }
        .navigationTitle(navTitle)
        .toolbar { toolbarContent }
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
    }

    private var navTitle: String {
        if let folder = selectedFolder {
            return "\(library.displayName()) • \(folder.name)"
        } else {
            return "\(library.displayName()) • Folders"
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if selectedFolder != nil {
                Button {
                    withAnimation { selectedFolder = nil }
                } label: {
                    Label("Back to Folders", systemImage: "chevron.left")
                }
            }
        }

        ToolbarItemGroup(placement: .automatic) {
            if selectedFolder != nil {
                Picker("Filter", selection: Binding(
                    get: { filter ?? .unknown },
                    set: { newValue in
                        filter = (newValue == .unknown) ? nil : newValue
                    })) {
                    Text("All").tag(MediaKind.unknown)
                    Text("Photos").tag(MediaKind.photo)
                    Text("Videos").tag(MediaKind.video)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
                .help("Filter by media type")
            }

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
        }
    }

    // MARK: - Folders Grid

    private var folderGrid: some View {
        let folders = library.folders()
        return Group {
            if folders.isEmpty {
                FriendlyUnavailableView(
                    title: "No folders",
                    systemImage: "folder",
                    description: Text("Connect a device, unlock it and tap “Trust”.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                        ForEach(folders) { folder in
                            folderCell(folder)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation { selectedFolder = folder }
                                }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    @ViewBuilder
    private func folderCell(_ folder: IOSMediaFolder) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
                Text(folder.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(folder.totalCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if folder.hasPhotos {
                    Label("Photos", systemImage: "photo")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.green.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                if folder.hasVideos {
                    Label("Videos", systemImage: "video")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.orange.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.secondary.opacity(0.2))
        )
    }

    // MARK: - Media Grid (inside folder)

    private func mediaList(in folder: IOSMediaFolder) -> some View {
        let items = library.items(in: folder.id, filter: filter)
        return Group {
            if items.isEmpty {
                FriendlyUnavailableView(
                    title: "No media in “\(folder.name)”",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Try a different folder or change the filter.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.offset) { pair in
                            let idx = pair.offset
                            let item = pair.element

                            mediaCell(item)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { open(index: idx, within: folder) }
                                .contextMenu {
                                    Button("Open") { open(index: idx, within: folder) }
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
                    .drawingGroup() // helps keep rendering smooth when scrolling
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

    private func open(index: Int, within folder: IOSMediaFolder) {
        // Build a transient array that matches indices with openFile API.
        // We use provider's "items(in:filter:)" to regenerate the same list,
        // then map back to flat "allItems" indices via names.
        let current = library.items(in: folder.id, filter: filter)
        guard index < current.count else { return }

        // In this UI, we just trigger the existing `openFile(at:)` by finding
        // the index of that item inside the legacy flat list.
        let flat = library.allItems()
        let name = current[index].name
        if let i = flat.firstIndex(where: { $0.name == name }) {
            openFile(atFlatIndex: i)
        }
    }

    private func openFile(atFlatIndex i: Int) {
        isOpening = false
        openURL = nil
        library.openFile(at: i) { url in
            DispatchQueue.main.async {
                if let url {
                    self.openURL = url
                    self.isOpening = true
                }
            }
        }
    }

    private func refresh() {
        // Hook if a manual refresh is added later.
    }

    // MARK: - Helpers

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
    @Published var flat: [IOSMediaItem] = [
        IOSMediaItem(name: "IMG_0001.JPG", byteSize: 1_234_567, created: Date(), pixelWidth: 4032, pixelHeight: 3024, kind: .photo, thumbnail: nil),
        IOSMediaItem(name: "IMG_0002.HEIC", byteSize: 1_834_567, created: Date(), pixelWidth: 4032, pixelHeight: 3024, kind: .photo, thumbnail: nil),
        IOSMediaItem(name: "VID_0003.MOV", byteSize: 12_834_567, created: Date(), pixelWidth: 1920, pixelHeight: 1080, kind: .video, thumbnail: nil)
    ]

    func allItems() -> [IOSMediaItem] { flat }
    func openFile(at index: Int, completion: @escaping (URL?) -> Void) { completion(nil) }

    func folders() -> [IOSMediaFolder] {
        [
            IOSMediaFolder(id: "photos", name: "DCIM", totalCount: flat.count, hasPhotos: true, hasVideos: true),
            IOSMediaFolder(id: "empty", name: "Empty", totalCount: 0, hasPhotos: false, hasVideos: false)
        ]
    }

    func items(in folderID: IOSFolderID, filter: MediaKind?) -> [IOSMediaItem] {
        guard folderID == "photos" else { return [] }
        guard let filter, filter != .unknown else { return flat }
        return flat.filter { $0.kind == filter }
    }

    func displayName() -> String { "Preview Device" }
}

struct DeviceMediaView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceMediaView(library: PreviewLibrary())
            .frame(width: 900, height: 600)
    }
}
#endif

