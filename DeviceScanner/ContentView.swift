
import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var manager: DeviceManager
    @State private var timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if manager.externalDrives.isEmpty && manager.iosDevices.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if !manager.externalDrives.isEmpty {
                            Section {
                                ForEach(manager.externalDrives) { drive in
                                    DriveRow(drive: drive)
                                        .padding(12)
                                        .background(.thinMaterial)
                                        .cornerRadius(12)
                                }
                            } header: {
                                Text("External Drives")
                                    .font(.headline)
                            }
                        }
                        if !manager.iosDevices.isEmpty {
                            Section {
                                ForEach(manager.iosDevices) { dev in
                                    IOSDeviceRow(device: dev)
                                        .padding(12)
                                        .background(.thinMaterial)
                                        .cornerRadius(12)
                                }
                            } header: {
                                Text("iOS Devices")
                                    .font(.headline)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 420)
        .onAppear {
            manager.scan()
        }
        .onReceive(timer) { _ in
            manager.scan()
        }
        .sheet(isPresented: $manager.showLogs) {
            LogView(logText: manager.logger.allText) {
                SavePanel.save(text: manager.logger.allText, suggestedFileName: "DeviceScanner-logs.txt")
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("DeviceScanner")
                    .font(.largeTitle).bold()
                Text("Finds external drives and iOS devices connected to this Mac.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                manager.scan()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button {
                manager.showLogs = true
            } label: {
                Label("View Diagnostics", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No devices found")
                .font(.title3).bold()
            Text("Connect a pendrive or an iPhone/iPad to see it here.")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    manager.scan()
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button {
                    manager.showLogs = true
                } label: {
                    Label("View Diagnostics", systemImage: "doc.text.magnifyingglass")
                }

                Button {
                    SavePanel.save(text: manager.logger.allText, suggestedFileName: "DeviceScanner-logs.txt")
                } label: {
                    Label("Save Logs…", systemImage: "square.and.arrow.down")
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
                .foregroundStyle(.quaternary)
        )
        .padding(.vertical, 24)
    }
}

private struct DriveRow: View {
    let drive: ExternalDrive

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 32))
            VStack(alignment: .leading, spacing: 4) {
                Text(drive.name)
                    .font(.headline)
                if let mount = drive.mountPoint?.path {
                    Text(mount)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Text("Type: \(drive.isRemovable ? "Removable" : "External")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let total = drive.totalCapacity {
                        Text("Capacity: \(ByteFormat.format(total))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let avail = drive.availableCapacity {
                        Text("Free: \(ByteFormat.format(avail))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
    }
}

private struct IOSDeviceRow: View {
    let device: IOSDevice

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 32))
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                if let sn = device.serialNumber, !sn.isEmpty {
                    Text("Serial: \(sn)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}
