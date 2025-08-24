//  IOSMediaLibrary.swift
//  DeviceScanner
//
//  Created by Kaden on 2/28/24.
//

import Foundation
import ImageCaptureCore
import AppKit
import UniformTypeIdentifiers

/// Handles opening a session with an iOS device (as an ICCameraDevice) and enumerating its photos/videos.
@MainActor
final class IOSMediaLibrary: NSObject, ObservableObject {
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var deviceName: String = "iOS Device"
    @Published private(set) var errorMessage: String?

    // Flat items are still used for backward-compatibility with existing UI,
    // but folder-first UI consumes folder APIs below.
    @Published private(set) var items: [IOSMediaItem] = []

    private let camera: ICCameraDevice
    private let logger: Logger

    // Map camera files to flat "items" indices (for openFile)
    private var fileToIndexMap: [ICCameraFile: Int] = [:]

    // Folders
    private var topLevelFolders: [ICCameraFolder] = []
    private var folderIdToFolder: [IOSFolderID: ICCameraFolder] = [:]
    private var folderIdToFiles: [IOSFolderID: [ICCameraFile]] = [:]

    // Thumbnails
    private var thumbnailRequests: Set<String> = []
    private var thumbnailCache: [String: NSImage] = [:] // fileName -> NSImage

    private var sessionOpened = false

    init(camera: ICCameraDevice, logger: Logger) {
        self.camera = camera
        self.logger = logger
        self.deviceName = camera.name ?? "iOS Device"
        super.init()
        self.camera.delegate = self
        openSession()
    }

    deinit {
        if sessionOpened {
            camera.requestCloseSession()
        }
    }

    // MARK: - Public (old) interface kept for compatibility

    func allItems() -> [IOSMediaItem] {
        return items
    }

    /// Downloads a file from the device to a temporary location and opens it
    func openFile(at index: Int, completion: @escaping (URL?) -> Void) {
        guard index < items.count else {
            completion(nil)
            return
        }

        let item = items[index]

        // Find the ICCameraFile for this item
        let cameraFile = fileToIndexMap.first { $0.value == index }?.key
        guard let file = cameraFile else {
            logger.log("Could not find camera file for item: \(item.name)")
            completion(nil)
            return
        }

        // Create temporary directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceScanner")
            .appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            logger.log("Failed to create temp directory: \(error)")
            completion(nil)
            return
        }

        let destinationURL = tempDir.appendingPathComponent(item.name)

        logger.log("Downloading \(item.name) to \(destinationURL.path)")

        // Read file data into memory and write it out
        let length: off_t
        #if swift(>=5.9)
        length = (file.fileSize as? off_t) ?? off_t(file.fileSize)
        #else
        length = off_t(file.fileSize)
        #endif

        file.requestReadData(atOffset: 0, length: length) { [weak self] data, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let error = error {
                    self.logger.log("Failed to read file data: \(error.localizedDescription)")
                    completion(nil)
                    return
                }

                guard let data = data else {
                    self.logger.log("No data received for file")
                    completion(nil)
                    return
                }

                do {
                    try data.write(to: destinationURL)
                    self.logger.log("Successfully downloaded \(item.name)")
                    completion(destinationURL)
                } catch {
                    self.logger.log("Failed to write file: \(error.localizedDescription)")
                    completion(nil)
                }
            }
        }
    }

    // MARK: - New folder-first APIs consumed by the view

    func folders() -> [IOSMediaFolder] {
        return topLevelFolders.map { folder in
            let id = folderId(for: folder)
            let files = folderIdToFiles[id] ?? []
            var photos = false
            var videos = false
            for f in files {
                let k = determineMediaKind(for: f)
                if k == .photo { photos = true }
                if k == .video { videos = true }
                if photos && videos { break }
            }
            return IOSMediaFolder(
                id: id,
                name: folder.name ?? "Untitled",
                totalCount: files.count,
                hasPhotos: photos,
                hasVideos: videos
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func items(in folderID: IOSFolderID, filter: MediaKind?) -> [IOSMediaItem] {
        let files = folderIdToFiles[folderID] ?? []
        let filteredFiles: [ICCameraFile]
        if let filter, filter != .unknown {
            filteredFiles = files.filter { determineMediaKind(for: $0) == filter }
        } else {
            filteredFiles = files
        }
        return makeItems(from: filteredFiles)
    }

    func displayName() -> String {
        deviceName
    }

    // MARK: - Session / Content

    private func openSession() {
        logger.log("Opening session with \(self.deviceName)...")
        self.isLoading = true
        self.errorMessage = nil
        camera.requestOpenSession()
    }

    private func processDeviceContents() {
        guard let contents = camera.contents else {
            self.logger.log("No contents found on device")
            self.isLoading = false
            return
        }

        // Build folder tree and per-folder file lists
        buildFolders(from: contents)

        // Also build flat items for backwards compatibility with existing menus/API
        let files = flatten(items: contents)
        self.logger.log("Found \(files.count) media files")
        self.items.removeAll()
        self.fileToIndexMap.removeAll()
        self.processFiles(files)
        self.isLoading = false
    }

    private func buildFolders(from roots: [ICCameraItem]) {
        topLevelFolders.removeAll()
        folderIdToFolder.removeAll()
        folderIdToFiles.removeAll()

        for item in roots {
            if let folder = item as? ICCameraFolder {
                topLevelFolders.append(folder)
                let id = folderId(for: folder)
                folderIdToFolder[id] = folder
                folderIdToFiles[id] = flatten(items: folder.contents ?? [])
            } else if item is ICCameraFile {
                // Some devices expose files at the root; group them into a pseudo-folder
                let pseudo = ICCameraFolder()
                pseudo.setValue("All Items", forKey: "name")
                topLevelFolders.append(pseudo)
                let id = folderId(for: pseudo)
                folderIdToFolder[id] = pseudo
                folderIdToFiles[id] = flatten(items: roots)
                break
            }
        }

        // If there were no folders, still expose a pseudo "All Items"
        if topLevelFolders.isEmpty {
            let pseudo = ICCameraFolder()
            pseudo.setValue("All Items", forKey: "name")
            topLevelFolders = [pseudo]
            let id = folderId(for: pseudo)
            folderIdToFolder[id] = pseudo
            folderIdToFiles[id] = flatten(items: roots)
        }
    }

    private func folderId(for folder: ICCameraFolder) -> IOSFolderID {
        // Use an object-identity-based string to be stable during session
        let oid = ObjectIdentifier(folder)
        return String(oid.hashValue, radix: 16)
    }

    private func flatten(items: [ICCameraItem]) -> [ICCameraFile] {
        var files: [ICCameraFile] = []
        for item in items {
            if let file = item as? ICCameraFile {
                files.append(file)
            } else if let folder = item as? ICCameraFolder, let children = folder.contents {
                files.append(contentsOf: flatten(items: children))
            }
        }
        return files
    }

    // Turn camera files into display models, using thumbnail cache.
    private func makeItems(from cameraFiles: [ICCameraFile]) -> [IOSMediaItem] {
        var result: [IOSMediaItem] = []
        for file in cameraFiles {
            let kind = determineMediaKind(for: file)
            guard kind != .unknown else { continue }

            let name = file.name ?? "Untitled"
            let cachedThumb = thumbnailCache[name]

            let item = IOSMediaItem(
                name: name,
                byteSize: file.fileSize,
                created: file.creationDate,
                pixelWidth: file.width as? Int,
                pixelHeight: file.height as? Int,
                kind: kind,
                thumbnail: cachedThumb
            )
            result.append(item)
        }
        return result
    }

    private func processFiles(_ cameraFiles: [ICCameraFile]) {
        for file in cameraFiles {
            let kind = determineMediaKind(for: file)
            guard kind != .unknown else { continue }

            let name = file.name ?? "Untitled"
            let item = IOSMediaItem(
                name: name,
                byteSize: file.fileSize,
                created: file.creationDate,
                pixelWidth: file.width as? Int,
                pixelHeight: file.height as? Int,
                kind: kind,
                thumbnail: thumbnailCache[name] // reuse if we have it
            )

            items.append(item)
            let index = items.count - 1
            fileToIndexMap[file] = index

            // Only request a thumbnail if not cached
            if thumbnailCache[name] == nil {
                requestThumbnail(for: file, at: index)
            }
        }
    }

    private func determineMediaKind(for file: ICCameraFile) -> MediaKind {
        guard let uti = file.uti?.lowercased() else {
            // Fallback to file extension
            let name = file.name?.lowercased() ?? ""
            if name.hasSuffix(".jpg") || name.hasSuffix(".jpeg") || name.hasSuffix(".png") ||
               name.hasSuffix(".heic") || name.hasSuffix(".heif") {
                return .photo
            } else if name.hasSuffix(".mov") || name.hasSuffix(".mp4") || name.hasSuffix(".m4v") {
                return .video
            }
            return .unknown
        }

        if uti.contains("public.movie") || uti.contains("video") || uti.contains("quicktime") {
            return .video
        } else if uti.contains("public.image") || uti.contains("jpeg") || uti.contains("heic") ||
                    uti.contains("png") || uti.contains("heif") {
            return .photo
        }

        return .unknown
    }

    private func requestThumbnail(for file: ICCameraFile, at index: Int) {
        let fileName = file.name ?? "unknown"

        // Avoid duplicate requests
        guard !thumbnailRequests.contains(fileName) else { return }
        thumbnailRequests.insert(fileName)

        logger.log("Requesting thumbnail for: \(fileName)")

        // Primary: request thumbnail data directly
        file.requestThumbnailData(options: nil) { [weak self] (data: Data?, error: Error?) in
            Task { @MainActor in
                guard let self = self,
                      index < self.items.count else { return }

                if let error = error {
                    self.logger.log("Thumbnail data error for \(fileName): \(error.localizedDescription)")
                } else if let data = data, let image = NSImage(data: data) {
                    self.logger.log("Successfully loaded thumbnail data for \(fileName)")
                    self.thumbnailCache[fileName] = image
                    self.items[index].thumbnail = image
                    return
                }

                // Fallback: if the ICCameraFile already has a CGImage thumbnail, use it
                if let cg = file.thumbnail {
                    self.logger.log("Using existing CGImage thumbnail for \(fileName)")
                    let rep = NSBitmapImageRep(cgImage: cg)
                    let image = NSImage(size: rep.size)
                    image.addRepresentation(rep)
                    self.thumbnailCache[fileName] = image
                    self.items[index].thumbnail = image
                } else {
                    self.logger.log("No thumbnail available for \(fileName)")
                }
            }
        }
    }

    private func rebuildFileMap() {
        fileToIndexMap.removeAll()
        thumbnailRequests.removeAll()

        // Rebuild mapping from current items and camera contents
        guard let contents = camera.contents else { return }
        let files = flatten(items: contents)

        for (index, item) in items.enumerated() {
            if let file = files.first(where: { $0.name == item.name }) {
                fileToIndexMap[file] = index
            }
        }
    }
}

// MARK: - ICDeviceDelegate
extension IOSMediaLibrary: ICDeviceDelegate {

    func deviceDidBecomeReady(_ device: ICDevice) {
        logger.log("Device became ready: \(device.name ?? "Unknown")")
    }

    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        if let error = error {
            logger.log("Failed to open session: \(error.localizedDescription)")
            self.errorMessage = "Failed to connect: \(error.localizedDescription)"
            self.isLoading = false
        } else {
            logger.log("Session opened successfully for \(device.name ?? "Unknown")")
            self.sessionOpened = true
            self.processDeviceContents()
        }
    }

    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        self.sessionOpened = false
        if let error = error {
            logger.log("Session closed with error: \(error.localizedDescription)")
        } else {
            logger.log("Session closed successfully")
        }
    }

    func didRemove(_ device: ICDevice) {
        logger.log("Device removed: \(device.name ?? "Unknown")")
        self.items.removeAll()
        self.fileToIndexMap.removeAll()
        self.thumbnailRequests.removeAll()
        self.isLoading = false
    }

    func device(_ device: ICDevice, didReceiveStatus status: [AnyHashable : Any]?) {
        if let status = status {
            logger.log("Device status update: \(status)")
        }
    }
}

// MARK: - ICCameraDeviceDelegate
extension IOSMediaLibrary: ICCameraDeviceDelegate {
    func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {
       // <#code#>
    }
    

    func cameraDeviceDidBecomeReady(_ camera: ICCameraDevice) {
        logger.log("Camera device ready: \(camera.name ?? "Unknown")")
        self.processDeviceContents()
    }

    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        logger.log("Device ready with complete content catalog")
        self.processDeviceContents()
    }

    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        logger.log("Access restriction removed")
        self.processDeviceContents()
    }

    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        logger.log("Access restriction enabled - clearing content")
        self.items.removeAll()
        self.fileToIndexMap.removeAll()
        self.thumbnailRequests.removeAll()
    }

    func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        let files = flatten(items: items)
        logger.log("Adding \(files.count) new files")
        self.processFiles(files)

        // Update per-folder maps for incremental adds
        if let contents = camera.contents {
            buildFolders(from: contents)
        }
    }

    func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
        var indicesToRemove: [Int] = []
        for item in items {
            if let file = item as? ICCameraFile, let index = self.fileToIndexMap[file] {
                indicesToRemove.append(index)
                self.fileToIndexMap.removeValue(forKey: file)
                if let name = file.name {
                    self.thumbnailCache.removeValue(forKey: name)
                }
            }
        }

        // Remove items in reverse order to maintain indices
        for index in indicesToRemove.sorted(by: >) {
            if index < self.items.count {
                self.items.remove(at: index)
            }
        }

        // Rebuild maps
        self.rebuildFileMap()
        if let contents = camera.contents {
            buildFolders(from: contents)
        }
    }

    func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {
        logger.log("Items renamed, refreshing content")
        self.items.removeAll()
        self.fileToIndexMap.removeAll()
        self.thumbnailRequests.removeAll()
        self.thumbnailCache.removeAll()
        self.processDeviceContents()
    }

    func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {
        guard let file = item as? ICCameraFile,
              let thumbnail = thumbnail,
              let index = fileToIndexMap[file],
              index < items.count else {
            if let error = error {
                logger.log("Thumbnail CGImage error for \(item.name ?? "unknown"): \(error.localizedDescription)")
            }
            return
        }

        logger.log("Received CGImage thumbnail for: \(item.name ?? "unknown")")
        let rep = NSBitmapImageRep(cgImage: thumbnail)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        if let name = file.name {
            thumbnailCache[name] = image
        }
        self.items[index].thumbnail = image
    }

    func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable : Any]?, for item: ICCameraItem, error: Error?) {
        if let error = error {
            logger.log("Metadata error for item: \(error.localizedDescription)")
        }
    }

    func cameraDevice(_ camera: ICCameraDevice, didEncounterError error: Error?) {
        if let error = error {
            self.logger.log("Camera error: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
        }
    }

    func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {
        logger.log("Camera capability changed")
    }
}

