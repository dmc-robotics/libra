import LibraKit
import SwiftUI

/// Mass, center of mass and the inertia tensor, in the current display units.
struct MassPropertiesView: View {
    let properties: MassProperties
    @DisplayUnitsSetting private var units

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 4) {
            GridRow {
                Text("Mass").foregroundStyle(.secondary).gridColumnAlignment(.leading)
                Text(Formatting.number(units.mass.fromSI(properties.mass))).fixedSize()
                Text(units.mass.symbol).foregroundStyle(.secondary)
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                ForEach(FrameAxis.allCases, id: \.self) { axis in
                    Text(axis.name.lowercased()).foregroundStyle(.secondary)
                }
            }
            GridRow {
                Text("COM").foregroundStyle(.secondary)
                ForEach(0..<3, id: \.self) { index in
                    Text(Formatting.number(units.length.fromSI(properties.centerOfMass[index]))).fixedSize()
                }
            }
            Divider().gridCellColumns(4)
            ForEach(FrameAxis.allCases, id: \.self) { row in
                GridRow {
                    Text("I\(row.name.lowercased())").foregroundStyle(.secondary)
                    ForEach(FrameAxis.allCases, id: \.self) { column in
                        Text(Formatting.number(units.inertia.fromSI(inertiaEntry(row, column)))).fixedSize()
                    }
                }
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .font(.callout)
        .textSelection(.enabled)
        .help("COM in \(units.length.symbol); inertia about the COM in \(units.inertia.symbol), rows and columns X, Y, Z")
    }

    /// Entries that are only integration noise next to the largest moment show as 0.
    private func inertiaEntry(_ row: FrameAxis, _ column: FrameAxis) -> Double {
        let inertia = properties.inertia
        let value = inertia.matrix[column.rawValue][row.rawValue]
        let scale = max(abs(inertia.xx), abs(inertia.yy), abs(inertia.zz))
        return abs(value) < scale * Formatting.relativeNoise ? 0 : value
    }
}

/// The selection's (or whole assembly's) totals over the bottom of the viewer.
struct TotalsBar: View {
    let document: LibraDocument
    let model: DocumentModel
    @DisplayUnitsSetting private var units

    var body: some View {
        let selectedIDs = model.selectedPartIDs(in: document)
        let summary = MassSummary(parts: selectedIDs.isEmpty ? document.parts : document.parts(selectedIDs))
        let properties = summary.expressed(in: document.libraFrame).properties
        let title = selectedIDs.isEmpty ? "Assembly" : "Selection"

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(title) · \(summary.partCount) parts").font(.headline)
                Spacer()
                Button {
                    copyToPasteboard(Formatting.summary(properties, title: "\(title) (Libra frame)", units: units))
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy these values")
            }
            if summary.unassignedCount > 0 {
                Label("\(summary.unassignedCount) without mass", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            MassPropertiesView(properties: properties)
            Text("Libra frame").font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .fixedSize()
        .background(.regularMaterial, in: .rect(cornerRadius: Layout.cornerRadius))
    }
}
