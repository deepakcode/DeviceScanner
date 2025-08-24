//
//  DeviceManager.swift
//  DeviceScanner
//
//  Created by Kaden on 2/28/24.
//

import Foundation
import Combine
import ImageCaptureCore

@MainActor
final class DeviceManager: ObservableObject {
    @Published var externalDrives: [ExternalDrive] = []
    @Published var iosDevices: [IOSDevice] = []
    @Published var showLogs: Bool = false

    let logger = Logger()
    private let iosBrowser = IOSDeviceBrowser()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        iosBrowser.$devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.iosDevices = devices
            }
            .store(in: &cancellables)
    }

    func scan() {
        logger.log("Starting device scan...")
        let drives = ExternalDriveScanner.scanExternalDrives()
        self.externalDrives = drives
        logger.log("Scan complete: \(drives.count) external drives, \(iosDevices.count) iOS devices.")
        if drives.isEmpty && iosDevices.isEmpty {
            logger.log("No devices found. Tip: Check your cable/ports. On iPhone, unlock and tap 'Trust'.")
        }
    }

    /// Create a media library controller for the given device, if connected.
    func makeMediaLibrary(for device: IOSDevice) -> IOSMediaLibrary? {
        guard let cam = iosBrowser.camera(for: device) else {
            logger.log("Selected device not available anymore: \(device.name)")
            return nil
        }
        return IOSMediaLibrary(camera: cam, logger: logger)
    }
}

// MARK: - External Drive Scanner (mounted volumes)

enum ExternalDriveScanner {
    static func scanExternalDrives() -> [ExternalDrive] {
        var found: [ExternalDrive] = []
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsInternalKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey
        ]

        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        for url in urls {
            do {
                let rv = try url.resourceValues(forKeys: Set(keys))
                let isInternal = rv.volumeIsInternal ?? true
                if isInternal { continue } // only external/additional volumes

                let name = rv.volumeName ?? url.lastPathComponent
                let total = rv.volumeTotalCapacity
                let free = rv.volumeAvailableCapacity
                let removable = rv.volumeIsRemovable ?? false
                let drive = ExternalDrive(
                    name: name,
                    mountPoint: url,
                    totalCapacity: total,
                    availableCapacity: free,
                    isRemovable: removable
                )
                found.append(drive)
            } catch {
                // ignore, non-fatal
            }
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
