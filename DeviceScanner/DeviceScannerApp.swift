
import SwiftUI

@main
struct DeviceScannerApp: App {
    @StateObject private var deviceManager = DeviceManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deviceManager)
        }
        .commands {
            CommandMenu("DeviceScanner") {
                Button("Refresh") {
                    deviceManager.scan()
                }.keyboardShortcut("r", modifiers: [.command])
                Button("View Diagnostics") {
                    deviceManager.showLogs = true
                }
            }
        }
    }
}
