//
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
final class IOSMediaLibrary: NSObject, ObservableObject {
    @Published private(set) var items: [IOSMediaItem] = []
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var deviceName: String = "iOS Device"
    @Published private(set) var errorMessage: String?

    private let camera: ICCameraDevice
    private let logger: Logger
    private var itemMap: [ICCameraItem: Int] = [:]
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

    func allItems() -> [IOSMediaItem] {
        return items
    }

    private func openSession() {
        DispatchQueue.main.async {
            self.logger.log("Opening session with \(self.deviceName)...")
            self.isLoading = true
            self.errorMessage = nil
        }
        camera.requestOpenSession()
    }

    private func processDeviceContents() {
        guard let contents = camera.contents else {
            DispatchQueue.main.async {
                self.logger.log("No contents found on device")
                self.isLoading = false
            }
            return
        }
        
        let files = flatten(items: contents)
        DispatchQueue.main.async {
            self.logger.log("Found \(files.count) media files")
            self.processFiles(files)
            self.isLoading = false
        }
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
            itemMap[file] = index

            // Request thumbnail
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
        file.requestThumbnailData(options: nil) { [weak self] (data: Data?, error: Error?) in
            DispatchQueue.main.async {
                guard let self = self,
                      index < self.items.count,
                      let data = data,
                      let image = NSImage(data: data) else { return }
                
                self.items[index].thumbnail = image
            }
        }
    }
    
    private func rebuildItemMap() {
        itemMap.removeAll()
        // Note: This is a simplified approach for rebuilding the map
        // In a production app, you might want a more sophisticated tracking system
    }
}

// MARK: - ICDeviceDelegate
extension IOSMediaLibrary: ICDeviceDelegate {
    
    func deviceDidBecomeReady(_ device: ICDevice) {
        DispatchQueue.main.async {
            self.logger.log("Device became ready: \(device.name ?? "Unknown")")
        }
    }
    
    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                self.logger.log("Failed to open session: \(error.localizedDescription)")
                self.errorMessage = "Failed to connect: \(error.localizedDescription)"
                self.isLoading = false
            } else {
                self.logger.log("Session opened successfully for \(device.name ?? "Unknown")")
                self.sessionOpened = true
                self.processDeviceContents()
            }
        }
    }
    
    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        DispatchQueue.main.async {
            self.sessionOpened = false
            if let error = error {
                self.logger.log("Session closed with error: \(error.localizedDescription)")
            } else {
                self.logger.log("Session closed successfully")
            }
        }
    }
    
    func didRemove(_ device: ICDevice) {
        DispatchQueue.main.async {
            self.logger.log("Device removed: \(device.name ?? "Unknown")")
            self.items.removeAll()
            self.itemMap.removeAll()
            self.isLoading = false
        }
    }
    
    @MainActor func device(_ device: ICDevice, didReceiveStatus status: [AnyHashable : Any]?) {
        // Optional: Handle status updates
        if let status = status {
            logger.log("Device status update: \(status)")
        }
    }
}

// MARK: - ICCameraDeviceDelegate
extension IOSMediaLibrary: ICCameraDeviceDelegate {
    
    func cameraDeviceDidBecomeReady(_ camera: ICCameraDevice) {
        DispatchQueue.main.async {
            self.logger.log("Camera device ready: \(camera.name ?? "Unknown")")
            self.processDeviceContents()
        }
    }
    
    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        DispatchQueue.main.async {
            self.logger.log("Device ready with complete content catalog")
            self.processDeviceContents()
        }
    }
    
    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        DispatchQueue.main.async {
            self.logger.log("Access restriction removed")
            self.processDeviceContents()
        }
    }
    
    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        DispatchQueue.main.async {
            self.logger.log("Access restriction enabled - clearing content")
            self.items.removeAll()
            self.itemMap.removeAll()
        }
    }
    
    func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        let files = flatten(items: items)
        DispatchQueue.main.async {
            self.logger.log("Adding \(files.count) new files")
            self.processFiles(files)
        }
    }
    
    func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
        DispatchQueue.main.async {
            var indicesToRemove: [Int] = []
            for item in items {
                if let index = self.itemMap[item] {
                    indicesToRemove.append(index)
                    self.itemMap.removeValue(forKey: item)
                }
            }
            
            // Remove items in reverse order to maintain indices
            for index in indicesToRemove.sorted(by: >) {
                if index < self.items.count {
                    self.items.remove(at: index)
                }
            }
            
            // Rebuild item map with new indices
            self.rebuildItemMap()
        }
    }
    
    func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {
        DispatchQueue.main.async {
            self.logger.log("Items renamed, refreshing content")
            // For simplicity, we'll refresh all content when items are renamed
            self.items.removeAll()
            self.itemMap.removeAll()
            self.processDeviceContents()
        }
    }
    
    func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {
        guard let thumbnail = thumbnail,
              let index = itemMap[item],
              index < items.count else { return }
        
        DispatchQueue.main.async {
            let rep = NSBitmapImageRep(cgImage: thumbnail)
            let image = NSImage(size: rep.size)
            image.addRepresentation(rep)
            self.items[index].thumbnail = image
        }
    }
    
    @MainActor func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable : Any]?, for item: ICCameraItem, error: Error?) {
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
            DispatchQueue.main.async {
                self.logger.log("Camera error: \(error.localizedDescription)")
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {
        DispatchQueue.main.async {
            self.logger.log("Camera capability changed")
        }
    }
}
