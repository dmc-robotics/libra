import LibraKit
import SwiftUI

/// Form rows for the center of mass and the inertia tensor, in the current display units.
struct MassPropertiesView: View {
    let properties: MassProperties
    @DisplayUnitsSetting private var units
    @AppStorage(Preferences.inertiaReferenceKey) private var inertiaReference = InertiaReference.centerOfMass

    var body: some View {
        let centerOfMass = properties.centerOfMass / units.length.siPerUnit
        LabeledContent("Center of Mass") {
            Text("\(Formatting.number(centerOfMass.x)), \(Formatting.number(centerOfMass.y)), \(Formatting.number(centerOfMass.z)) \(units.length.symbol)")
        }
        .help("x, y, z")
        Picker("Inertia About", selection: $inertiaReference) {
            ForEach(InertiaReference.allCases) { reference in
                Text(reference.name).tag(reference)
            }
        }
        .pickerStyle(.segmented)
        .help("Show inertia about the center of mass or about the origin of the frame these values are in")
        VStack(alignment: .leading, spacing: 6) {
            Text("Inertia (\(units.inertia.symbol))")
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 3) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    ForEach(FrameAxis.allCases, id: \.self) { axis in
                        Text(axis.name.lowercased()).foregroundStyle(.tertiary)
                    }
                }
                ForEach(FrameAxis.allCases, id: \.self) { row in
                    GridRow {
                        Text(row.name.lowercased()).foregroundStyle(.tertiary)
                        ForEach(FrameAxis.allCases, id: \.self) { column in
                            // Grey like the other read-only values
                            Text(Formatting.number(units.inertia.fromSI(inertiaEntry(row, column))))
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .help("About \(inertiaReference.phrase). Off-diagonal values are tensor entries (Ixy = −∫xy dm).")
        }
        .monospacedDigit()
        .lineLimit(1)
        // Long values shrink a little in a narrow inspector instead of being cut off
        .minimumScaleFactor(Layout.minimumTextScale)
        .textSelection(.enabled)
    }

    /// Entries that are only integration noise next to the largest moment show as 0.
    private func inertiaEntry(_ row: FrameAxis, _ column: FrameAxis) -> Double {
        let inertia = properties.inertia(about: inertiaReference)
        let value = inertia.matrix[column.rawValue][row.rawValue]
        let scale = max(abs(inertia.xx), abs(inertia.yy), abs(inertia.zz))
        return abs(value) < scale * Formatting.relativeNoise ? 0 : value
    }
}

/// A read-only mass, in the current display units.
struct MassRow: View {
    let mass: Double
    @DisplayUnitsSetting private var units

    var body: some View {
        LabeledContent("Mass") {
            Text("\(Formatting.number(units.mass.fromSI(mass))) \(units.mass.symbol)")
        }
    }
}

/// An inspector section with the full mass properties and a copy button.
struct MassPropertiesSection<MassRows: View>: View {
    /// Already expressed in the frame named by `frameName`.
    let summary: MassSummary
    let frameName: String
    /// Shown first, e.g. a field to edit a part's mass. A read-only total by default.
    let massRows: MassRows
    @DisplayUnitsSetting private var units
    @AppStorage(Preferences.inertiaReferenceKey) private var inertiaReference = InertiaReference.centerOfMass

    init(summary: MassSummary, frameName: String, @ViewBuilder massRows: () -> MassRows) {
        self.summary = summary
        self.frameName = frameName
        self.massRows = massRows()
    }

    var body: some View {
        Section {
            if summary.unassignedCount > 0 {
                Label("\(summary.unassignedCount) of \(summary.partCount) parts without mass", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            massRows
            MassPropertiesView(properties: summary.properties)
        } header: {
            HStack {
                Text("Mass Properties")
                Spacer()
                Button {
                    copyToPasteboard(Formatting.summary(summary.properties, title: "Mass properties (\(frameName))", units: units, inertiaReference: inertiaReference))
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Copy these values")
            }
        } footer: {
            Text("In the \(frameName). Inertia is about \(inertiaReference.phrase).")
        }
    }
}

extension MassPropertiesSection where MassRows == MassRow {
    init(summary: MassSummary, frameName: String) {
        self.init(summary: summary, frameName: frameName) { MassRow(mass: summary.properties.mass) }
    }
}

extension InertiaReference {
    var name: String {
        switch self {
        case .centerOfMass: "COM"
        case .origin: "Origin"
        }
    }

    /// For sentences, e.g. "Inertia is about the center of mass".
    var phrase: String {
        switch self {
        case .centerOfMass: "the center of mass"
        case .origin: "the frame's origin"
        }
    }
}
