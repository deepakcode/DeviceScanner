//
//  IOSDeviceBrowser.swift
//  DeviceScanner
//
//  Created by Kaden on 2/28/24.
//

import Foundation
import ImageCaptureCore

/// Publishes connected iOS devices (as cameras exposed by Image Capture).
final class IOSDeviceBrowser: NSObject, ObservableObject {
    @Published var devices: [IOSDevice] = []

    private let browser = ICDeviceBrowser()
    private var camerasBySerial: [String: ICCameraDevice] = [:]
    private var camerasByName: [String: ICCameraDevice] = [:]

    override init() {
        super.init()
        browser.delegate = self
        browser.browsedDeviceTypeMask = .camera
        browser.start()
    }

    deinit {
        browser.stop()
    }

    /// Returns the underlying ICCameraDevice for a given IOSDevice, if still connected.
    func camera(for device: IOSDevice) -> ICCameraDevice? {
        if let sn = device.serialNumber, let cam = camerasBySerial[sn] {
            return cam
        }
        return camerasByName[device.name]
    }
}

extension IOSDeviceBrowser: ICDeviceBrowserDelegate {
    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let cam = device as? ICCameraDevice else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let ios = IOSDevice(
                name: cam.name ?? "iOS Device",
                serialNumber: cam.serialNumberString,
                vendorId: nil,
                productId: nil
            )
            
            // Avoid duplicates
            if !self.devices.contains(where: { $0.serialNumber == ios.serialNumber && $0.name == ios.name }) {
                self.devices.append(ios)
            }
            
            // Store camera references
            if let sn = cam.serialNumberString {
                self.camerasBySerial[sn] = cam
            }
            if let name = cam.name {
                self.camerasByName[name] = cam
            }
        }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        guard let cam = device as? ICCameraDevice else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.devices.removeAll { $0.serialNumber == cam.serialNumberString || $0.name == cam.name }
            
            if let sn = cam.serialNumberString {
                self.camerasBySerial.removeValue(forKey: sn)
            }
            if let name = cam.name {
                self.camerasByName.removeValue(forKey: name)
            }
        }
    }
    
    func deviceBrowser(_ browser: ICDeviceBrowser, requestsSelect device: ICDevice) {
        // Optional: Handle device selection
    }
}
