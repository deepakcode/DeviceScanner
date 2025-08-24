//
//  Logger.swift
//  DeviceScanner
//
//  Created by Kaden on 2/28/24.
//

import Foundation
import AppKit

@MainActor
final class Logger: ObservableObject {
    @Published private(set) var lines: [String] = []

    var allText: String {
        lines.joined(separator: "\n")
    }

    func log(_ message: String) {
        let stamp = Self.timestamp()
        let entry = "[\(stamp)] \(message)"
        lines.append(entry)
        print(entry)
        
        // Keep only last 1000 lines to prevent memory issues
        if lines.count > 1000 {
            lines.removeFirst(lines.count - 1000)
        }
    }

    func clear() {
        lines.removeAll()
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}

enum SavePanel {
    static func save(text: String, suggestedFileName: String) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = suggestedFileName
        panel.isExtensionHidden = false
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            do {
                try text.data(using: .utf8)?.write(to: url)
            } catch {
                NSSound.beep()
            }
        }
    }
}

enum NSPasteboardHelper {
    static func copy(text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
