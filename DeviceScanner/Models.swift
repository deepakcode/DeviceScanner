
import Foundation

struct ExternalDrive: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let mountPoint: URL?
    let totalCapacity: Int?
    let availableCapacity: Int?
    let isRemovable: Bool
}

struct IOSDevice: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let serialNumber: String?
    let vendorId: Int?
    let productId: Int?
}

enum ByteFormat {
    static func format(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024.0
        if gb < 1024 { return String(format: "%.2f GB", gb) }
        let tb = gb / 1024.0
        return String(format: "%.2f TB", tb)
    }
}
