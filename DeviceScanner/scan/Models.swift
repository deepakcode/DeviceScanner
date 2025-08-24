//  Models.swift
//  DeviceScanner
//
//  Created by Kaden on 2/28/24.
//

import Foundation
import AppKit

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

enum MediaKind: String, CaseIterable {
    case photo
    case video
    case unknown

    var displayName: String {
        switch self {
        case .photo: return "Photo"
        case .video: return "Video"
        case .unknown: return "Unknown"
        }
    }
}

struct IOSMediaItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let byteSize: Int64?
    let created: Date?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let kind: MediaKind
    var thumbnail: NSImage?

    static func == (lhs: IOSMediaItem, rhs: IOSMediaItem) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Folders

/// Stable identifier for a camera folder for this session.
typealias IOSFolderID = String

struct IOSMediaFolder: Identifiable, Hashable {
    let id: IOSFolderID
    let name: String
    let totalCount: Int
    let hasPhotos: Bool
    let hasVideos: Bool
}

