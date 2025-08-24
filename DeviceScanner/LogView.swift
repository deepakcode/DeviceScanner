import SwiftUI

struct LogView: View {
    let logText: String
    var onSave: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnostics")
                    .font(.title2).bold()
                Spacer()
                Button {
                    onSave()
                } label: {
                    Label("Save Logs…", systemImage: "square.and.arrow.down")
                }
                Button {
                    NSPasteboardHelper.copy(text: logText)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }

            ScrollView {
                Text(logText.isEmpty ? "No logs yet." : logText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
            }

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 420)
    }
}
