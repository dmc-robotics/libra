import LibraKit
import SwiftUI

/// Form rows for mass, center of mass and the inertia tensor, in the current display units.
struct MassPropertiesView: View {
    let properties: MassProperties
    @DisplayUnitsSetting private var units

    var body: some View {
        let centerOfMass = properties.centerOfMass / units.length.siPerUnit
        LabeledContent("Mass") {
            Text("\(Formatting.number(units.mass.fromSI(properties.mass))) \(units.mass.symbol)")
        }
        LabeledContent("Center of Mass") {
            Text("\(Formatting.number(centerOfMass.x)), \(Formatting.number(centerOfMass.y)), \(Formatting.number(centerOfMass.z)) \(units.length.symbol)")
        }
        .help("x, y, z")
        VStack(alignment: .leading, spacing: 6) {
            Text("Inertia (\(units.inertia.symbol))")
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 3) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    ForEach(FrameAxis.allCases, id: \.self) { axis in
                        Text(axis.name.lowercased()).foregroundStyle(.secondary)
                    }
                }
                ForEach(FrameAxis.allCases, id: \.self) { row in
                    GridRow {
                        Text(row.name.lowercased()).foregroundStyle(.secondary)
                        ForEach(FrameAxis.allCases, id: \.self) { column in
                            Text(Formatting.number(units.inertia.fromSI(inertiaEntry(row, column))))
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .help("About the center of mass. Off-diagonal values are tensor entries (Ixy = −∫xy dm).")
        }
        .monospacedDigit()
        .lineLimit(1)
        // Long values shrink a little in a narrow inspector instead of being cut off
        .minimumScaleFactor(Layout.minimumTextScale)
        .textSelection(.enabled)
    }

    /// Entries that are only integration noise next to the largest moment show as 0.
    private func inertiaEntry(_ row: FrameAxis, _ column: FrameAxis) -> Double {
        let inertia = properties.inertia
        let value = inertia.matrix[column.rawValue][row.rawValue]
        let scale = max(abs(inertia.xx), abs(inertia.yy), abs(inertia.zz))
        return abs(value) < scale * Formatting.relativeNoise ? 0 : value
    }
}

/// An inspector section with the full mass properties and a copy button.
struct MassPropertiesSection: View {
    /// Already expressed in the frame named by `frameName`.
    let summary: MassSummary
    let frameName: String
    @DisplayUnitsSetting private var units

    var body: some View {
        Section {
            if summary.unassignedCount > 0 {
                Label("\(summary.unassignedCount) of \(summary.partCount) parts without mass", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            MassPropertiesView(properties: summary.properties)
        } header: {
            HStack {
                Text("Mass Properties")
                Spacer()
                Button {
                    copyToPasteboard(Formatting.summary(summary.properties, title: "Mass properties (\(frameName))", units: units))
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Copy these values")
            }
        } footer: {
            Text("In the \(frameName). Inertia is about the center of mass.")
        }
    }
}
