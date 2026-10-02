import LibraKit
import SwiftUI

/// The strip under the viewer: totals for the selection (or the whole assembly), or instructions while picking.
struct StatusBar: View {
    @Binding var document: LibraDocument
    let model: DocumentModel
    @DisplayUnitsSetting private var units

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                if model.tool == .select {
                    totals
                } else {
                    pickingStatus
                }
            }
            .font(.callout)
            .lineLimit(1)
            .padding(.horizontal, 12)
            // Never let the status text set the viewer column's minimum width; clip it instead.
            // A content-driven minimum here crashed the window when it was resized (see WindowResizeTests).
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: Layout.statusBarHeight, maxHeight: Layout.statusBarHeight, alignment: .leading)
            .clipped()
        }
        .background(.bar)
    }

    @ViewBuilder
    private var totals: some View {
        let selectedIDs = model.selectedPartIDs(in: document)
        let parts = selectedIDs.isEmpty ? document.parts : document.parts(selectedIDs)
        let summary = MassSummary(parts: parts).expressed(in: document.libraFrame)
        Text(selectedIDs.isEmpty ? "Assembly, \(summary.partCount) parts" : "\(summary.partCount) of \(document.parts.count) parts selected")
        if summary.properties.mass > 0 {
            labeled("Mass", "\(Formatting.number(units.mass.fromSI(summary.properties.mass))) \(units.mass.symbol)")
            labeled("COM", "\(Formatting.vector(summary.properties.centerOfMass / units.length.siPerUnit)) \(units.length.symbol)")
        }
        Spacer(minLength: 0)
        if summary.unassignedCount > 0 {
            Button {
                model.selection = Set(parts.filter { $0.massProperties == nil }.map { .part($0.id) })
            } label: {
                Label("\(summary.unassignedCount) without mass", systemImage: "exclamationmark.triangle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.orange)
            .help("Select the parts that have no mass yet")
        }
    }

    @ViewBuilder
    private var pickingStatus: some View {
        Image(systemName: "scope").foregroundStyle(.tint)
        Text(instruction)
        if let snap = model.hoverSnap {
            Text(snap.kind.name).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Button("Cancel") { model.tool = .select }
            .controlSize(.small)
            .keyboardShortcut(.cancelAction)
    }

    private var instruction: String {
        switch model.tool {
        case .select: ""
        case .pickOrigin: "Click a hole or shaft edge, a face or a corner to place the origin"
        case .pickDirection(_, let axis): "Click a shaft, face or edge to aim \(axis.name)"
        }
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }
}
