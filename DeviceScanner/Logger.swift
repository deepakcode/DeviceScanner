
import Foundation
import AppKit

@MainActor
final class Logger {
    private(set) var lines: [String] = []

    var allText: String {
        lines.joined(separator: "\n")
    }

    func log(_ message: String) {
        let stamp = Self.timestamp()
        let entry = "[\(stamp)] \(message)"
        lines.append(entry)
        print(entry)
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
