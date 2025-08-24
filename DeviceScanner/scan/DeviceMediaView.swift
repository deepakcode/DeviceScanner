//
//  DeviceMediaView.swift
//  DeviceScanner
//
//  Created by Kaden on 2/28/24.
//

import SwiftUI
import ImageCaptureCore

struct DeviceMediaView: View {
    @EnvironmentObject var manager: DeviceManager
    let device: IOSDevice

    @StateObject private var libraryHolder = LibraryHolder()

    var body: some View {
        Group {
            if let lib = libraryHolder.library {
                MediaGrid(library: lib, deviceName: lib.deviceName)
                    .navigationTitle(lib.deviceName)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                libraryHolder.refresh(with: manager.makeMediaLibrary(for: device))
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                    }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Connecting to \(device.name)…")
                        .foregroundStyle(.secondary)
                    Text("Make sure the device is unlocked and you tap 'Trust' if prompted")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .onAppear {
                    if libraryHolder.library == nil {
                        libraryHolder.attach(manager.makeMediaLibrary(for: device))
                    }
                }
                .navigationTitle(device.name)
            }
        }
        .frame(minWidth: 900, minHeight: 620)
    }

    @MainActor
    private final class LibraryHolder: ObservableObject {
        @Published var library: IOSMediaLibrary?

        func attach(_ lib: IOSMediaLibrary?) {
            self.library = lib
        }

        func refresh(with newLibrary: IOSMediaLibrary?) {
            self.library = newLibrary
        }
    }
}

private struct MediaGrid: View {
    @ObservedObject var library: IOSMediaLibrary
    let deviceName: String

    @State private var searchText: String = ""
    @State private var filter: Filter = .all
    @State private var sortOption: SortOption = .name

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case photos = "Photos"
        case videos = "Videos"
        var id: String { rawValue }
    }
    
    enum SortOption: String, CaseIterable, Identifiable {
        case name = "Name"
        case date = "Date"
        case size = "Size"
        var id: String { rawValue }
    }

    private var filtered: [IOSMediaItem] {
        let base = library.allItems()
        
        // Apply filter
        let filtered: [IOSMediaItem]
        switch filter {
        case .all:
            filtered = base
        case .photos:
            filtered = base.filter { $0.kind == .photo }
        case .videos:
            filtered = base.filter { $0.kind == .video }
        }
        
        // Apply search
        let searched = searchText.isEmpty ?
            filtered :
            filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        
        // Apply sorting
        return searched.sorted { item1, item2 in
            switch sortOption {
            case .name:
                return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
            case .date:
                guard let date1 = item1.created, let date2 = item2.created else {
                    return item1.created != nil
                }
                return date1 > date2 // Most recent first
            case .size:
                let size1 = item1.byteSize ?? 0
                let size2 = item2.byteSize ?? 0
                return size1 > size2 // Largest first
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Controls
            HStack {
                // Filter picker
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                
                // Sort picker
                Picker("Sort", selection: $sortOption) {
                    ForEach(SortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)

                Spacer()

                // Search field
                TextField("Search by name…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
            }
            
            // Stats
            HStack {
                Text("\(filtered.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if library.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("Loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }

            // Content
            if library.isLoading && library.allItems().isEmpty {
                VStack(spacing: 12) {
                    ProgressView("Loading media from \(deviceName)…")
                    Text("Unlock the iPhone and tap 'Trust This Computer' if prompted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = library.errorMessage {
                FriendlyUnavailableView(
                    title: "Connection Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if filtered.isEmpty {
                let title = searchText.isEmpty ? "No media found" : "No matching media"
                let description = searchText.isEmpty ?
                    "No photos or videos are available on this device or access was not granted." :
                    "Try adjusting your search terms or filter settings."
                
                FriendlyUnavailableView(
                    title: title,
                    description: Text(description)
                )
            } else {
                ScrollView {
                    let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)]
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filtered) { item in
                            MediaCell(item: item, isLoading: library.isLoading)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(16)
    }
}

private struct MediaCell: View {
    let item: IOSMediaItem
    let isLoading: Bool
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(height: 140)

                if let img = item.thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: item.kind == .video ? "video.fill" : "photo.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                }
                
                // Video indicator
                if item.kind == .video {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .background(Circle().fill(.black.opacity(0.3)))
                        }
                        Spacer()
                    }
                    .padding(8)
                }
                
                // Hover overlay
                if isHovered {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.blue.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.blue, lineWidth: 2)
                        )
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .help(item.name)

                HStack(spacing: 8) {
                    // File size
                    if let size = item.byteSize {
                        Text(ByteFormat.format(Int(size)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Media type badge
                    HStack(spacing: 2) {
                        Image(systemName: item.kind == .video ? "film" : "camera")
                        Text(item.kind.displayName)
                    }
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
                
                // Date
                if let date = item.created {
                    Text(date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                // Dimensions
                if let width = item.pixelWidth, let height = item.pixelHeight {
                    Text("\(width) × \(height)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
    }
}
