import Foundation
import ImageCaptureCore

/// Publishes connected iOS devices (as cameras exposed by Image Capture).
final class IOSDeviceBrowser: NSObject, ObservableObject {
    @Published var devices: [IOSDevice] = []

    private let browser = ICDeviceBrowser()

    override init() {
        super.init()
        browser.delegate = self

        // Use explicit rawValue for the camera device type mask to avoid optional unwrapping issues
        // ICDeviceTypeMaskCamera has raw value 0x1 on macOS SDKs.
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: 0x00000001)!

        browser.start()
    }
}

extension IOSDeviceBrowser: ICDeviceBrowserDelegate {
    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let cam = device as? ICCameraDevice else { return }
        let ios = IOSDevice(
            name: cam.name ?? "iOS Device",
            serialNumber: cam.serialNumberString,
            vendorId: nil,
            productId: nil
        )
        if !devices.contains(where: { $0.serialNumber == ios.serialNumber && $0.name == ios.name }) {
            devices.append(ios)
        }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        guard let cam = device as? ICCameraDevice else { return }
        devices.removeAll { $0.serialNumber == cam.serialNumberString || $0.name == cam.name }
    }
}
