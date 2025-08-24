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
    @Published private(set) var items: [IOSMediaItem] = []
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var deviceName: String = "iOS Device"
    @Published private(set) var errorMessage: String?

    private let camera: ICCameraDevice
    private let logger: Logger
    private var fileToIndexMap: [ICCameraFile: Int] = [:]
    private var sessionOpened = false
    
    // Track thumbnail requests to avoid duplicates
    private var thumbnailRequests: Set<String> = []

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
        
        let files = flatten(items: contents)
        self.logger.log("Found \(files.count) media files")
        self.processFiles(files)
        self.isLoading = false
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

    private func processFiles(_ cameraFiles: [ICCameraFile]) {
        for file in cameraFiles {
            let kind = determineMediaKind(for: file)
            
            // Skip non-media files
            guard kind != .unknown else { continue }

            let item = IOSMediaItem(
                name: file.name ?? "Untitled",
                byteSize: file.fileSize,
                created: file.creationDate,
                pixelWidth: file.width as? Int,
                pixelHeight: file.height as? Int,
                kind: kind,
                thumbnail: nil
            )
            
            items.append(item)
            let index = items.count - 1
            fileToIndexMap[file] = index

            // Request thumbnail with improved error handling
            requestThumbnail(for: file, at: index)
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
                    self.items[index].thumbnail = image
                    return
                }
                
                // Fallback: if the ICCameraFile already has a CGImage thumbnail, use it
                if let cg = file.thumbnail {
                    self.logger.log("Using existing CGImage thumbnail for \(fileName)")
                    let rep = NSBitmapImageRep(cgImage: cg)
                    let image = NSImage(size: rep.size)
                    image.addRepresentation(rep)
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
        // Optional: Handle status updates
        if let status = status {
            logger.log("Device status update: \(status)")
        }
    }
}

// MARK: - ICCameraDeviceDelegate
extension IOSMediaLibrary: ICCameraDeviceDelegate {
    
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
    }
    
    func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
        var indicesToRemove: [Int] = []
        for item in items {
            if let file = item as? ICCameraFile, let index = self.fileToIndexMap[file] {
                indicesToRemove.append(index)
                self.fileToIndexMap.removeValue(forKey: file)
            }
        }
        
        // Remove items in reverse order to maintain indices
        for index in indicesToRemove.sorted(by: >) {
            if index < self.items.count {
                self.items.remove(at: index)
            }
        }
        
        // Rebuild file map with new indices
        self.rebuildFileMap()
    }
    
    func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {
        logger.log("Items renamed, refreshing content")
        // For simplicity, we'll refresh all content when items are renamed
        self.items.removeAll()
        self.fileToIndexMap.removeAll()
        self.thumbnailRequests.removeAll()
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
        self.items[index].thumbnail = image
    }
    
    func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable : Any]?, for item: ICCameraItem, error: Error?) {
        // Optional: Process metadata if needed
        if let error = error {
            logger.log("Metadata error for item: \(error.localizedDescription)")
        }
    }
    
    func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {
        // Optional: Handle PTP events
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
