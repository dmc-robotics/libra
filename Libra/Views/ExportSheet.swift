import AppKit
import LibraKit
import SwiftUI

struct ExportSheet: View {
    let report: MassReport
    let fileName: String
    @Environment(\.dismiss) private var dismiss
    @State private var kind = ExportKind.mjcf

    var body: some View {
        let text = kind.text(for: report)
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Mass Properties")
                .font(.headline)
            Picker("Format", selection: $kind) {
                ForEach(ExportKind.allCases) { kind in
                    Text(kind.name).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if report.assembly.unassignedCount > 0 {
                Label("\(report.assembly.unassignedCount) parts have no mass and are left out.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            ScrollView([.vertical, .horizontal]) {
                Text(text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(.background.secondary, in: .rect(cornerRadius: 6))
            HStack {
                Text("SI units. Groups are in their own frames, posed relative to the Libra frame.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy") { copyToPasteboard(text) }
                Button("Save…") { save(text) }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: Layout.exportSheetWidth, height: Layout.exportSheetHeight)
    }

    private func save(_ text: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(fileName).\(kind.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
