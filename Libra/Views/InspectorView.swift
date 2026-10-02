import LibraKit
import SwiftUI

/// Shows whatever is selected: one body, some parts, or (with nothing selected) the Libra frame.
struct InspectorView: View {
    @Binding var document: LibraDocument
    @Bindable var model: DocumentModel

    var body: some View {
        Form {
            if let body = model.selectedBody(in: document) {
                BodyInspector(bodyID: body.id, document: $document, model: model)
            } else {
                let partIDs = model.selectedPartIDs(in: document)
                if partIDs.isEmpty {
                    LibraFrameInspector(document: $document, model: model)
                } else {
                    PartsInspector(partIDs: partIDs, document: $document, model: model)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct LibraFrameInspector: View {
    @Binding var document: LibraDocument
    @Bindable var model: DocumentModel

    var body: some View {
        Section {
            FrameEditor(target: .libra, document: $document, model: model)
        } header: {
            Text("Libra Frame")
        } footer: {
            Text("The reference for totals, standard views and export. Usually the robot's base: pick its origin and aim its axes (Z up).")
        }
        Section("Assembly") {
            AssignmentCounts(parts: document.parts)
        }
    }
}

private struct AssignmentCounts: View {
    let parts: [Part]

    var body: some View {
        let unassigned = parts.filter { $0.massProperties == nil }.count
        LabeledContent("Parts", value: "\(parts.count)")
        LabeledContent("Without mass", value: "\(unassigned)")
    }
}

// MARK: Bodies

private struct BodyInspector: View {
    let bodyID: UUID
    @Binding var document: LibraDocument
    @Bindable var model: DocumentModel

    private var index: Int? {
        document.bodies.firstIndex { $0.id == bodyID }
    }

    var body: some View {
        if let index {
            let body = document.bodies[index]
            let summary = MassSummary(parts: document.parts(body.partIDs))
            Section("Body") {
                TextField("Name", text: $document.bodies[index].name)
                LabeledContent("Parts", value: "\(summary.partCount)")
                if summary.unassignedCount > 0 {
                    Label("\(summary.unassignedCount) without mass", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Button("Select Parts") {
                    model.selection = Set(body.partIDs.map(SidebarItem.part))
                }
            }
            Section("Body Frame") {
                FrameEditor(target: .body(bodyID), document: $document, model: model)
            }
            Section {
                MassPropertiesView(properties: summary.properties.mass > 0 ? summary.properties.expressed(in: body.frame) : summary.properties)
            } header: {
                Text("Properties in Body Frame")
            }
            Section {
                Button("Delete Body", role: .destructive) {
                    model.deleteBody(bodyID, in: &document)
                }
            }
        }
    }
}

// MARK: Parts

private enum MassKind: String, CaseIterable, Identifiable {
    case unassigned = "None"
    case measured = "Measured"
    case override = "Override"

    var id: Self { self }

    init(_ assignment: MassAssignment) {
        switch assignment {
        case .unassigned: self = .unassigned
        case .measured: self = .measured
        case .override: self = .override
        }
    }
}

private struct PartsInspector: View {
    let partIDs: Set<UUID>
    @Binding var document: LibraDocument
    @Bindable var model: DocumentModel
    @DisplayUnitsSetting private var units
    @State private var massForEach = 0.0

    private var parts: [Part] { document.parts(partIDs) }

    var body: some View {
        if parts.count == 1, let part = parts.first, let index = document.parts.firstIndex(where: { $0.id == part.id }) {
            singlePart(part, index: index)
        } else {
            multipleParts
        }
        bodySection
        Section {
            let summary = MassSummary(parts: parts)
            if summary.unassignedCount > 0 {
                Label("\(summary.unassignedCount) of \(summary.partCount) without mass", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            MassPropertiesView(properties: summary.properties.mass > 0 ? summary.properties.expressed(in: document.libraFrame) : summary.properties)
        } header: {
            Text("Properties in Libra Frame")
        }
    }

    // MARK: One part

    @ViewBuilder
    private func singlePart(_ part: Part, index: Int) -> some View {
        Section("Part") {
            LabeledContent("Name", value: part.name)
            if part.definitionName != part.name {
                LabeledContent("Component", value: part.definitionName)
            }
            if !part.path.isEmpty {
                LabeledContent("Assembly", value: part.path.joined(separator: " › "))
            }
            LabeledContent("Volume") {
                Text("\(Formatting.number(part.volumeProperties.volume / pow(units.length.siPerUnit, 3))) \(units.length.symbol)³")
            }
            if !part.hasVolume {
                Label("No closed volume (a surface body?). Use an override.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Button("Select All \(part.definitionName) Instances") {
                model.selection = Set(document.parts.filter { $0.definitionName == part.definitionName }.map { .part($0.id) })
            }
        }
        Section("Mass") {
            Picker("Source", selection: kindBinding(index)) {
                ForEach(MassKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            switch part.mass {
            case .unassigned:
                EmptyView()
            case .measured(let mass):
                NumberField(title: "Mass", value: measuredBinding(index), unit: units.mass.symbol)
                if part.hasVolume {
                    // g/cm³ is a handy sanity check against the material
                    LabeledContent("Density", value: "\(Formatting.number(mass / part.volumeProperties.volume / 1000)) g/cm³")
                }
            case .override:
                overrideFields(index)
            }
        }
        if case .override = part.mass {
            Section {
                FrameEditor(target: .override(part.id), document: $document, model: model)
            } header: {
                Text("Override Frame")
            } footer: {
                Text("The center of mass and inertia above are entered in this frame, e.g. a datasheet's axes.")
            }
        }
    }

    private func kindBinding(_ index: Int) -> Binding<MassKind> {
        Binding {
            MassKind(document.parts[index].mass)
        } set: { kind in
            let part = document.parts[index]
            let current = part.massProperties
            switch kind {
            case .unassigned:
                document.parts[index].mass = .unassigned
            case .measured:
                document.parts[index].mass = .measured(current?.mass ?? 0)
            case .override:
                // Start from the current values, in the Libra frame
                let frame = document.libraFrame
                let local = current?.expressed(in: frame)
                document.parts[index].mass = .override(MassOverride(
                    mass: local?.mass ?? 0,
                    centerOfMass: local?.centerOfMass ?? frame.localPoint(part.volumeProperties.centroid),
                    inertia: local?.inertia ?? .zero,
                    frame: frame
                ))
            }
        }
    }

    private func measuredBinding(_ index: Int) -> Binding<Double> {
        Binding {
            if case .measured(let mass) = document.parts[index].mass { units.mass.fromSI(mass) } else { 0 }
        } set: {
            document.parts[index].mass = .measured(units.mass.toSI($0))
        }
    }

    @ViewBuilder
    private func overrideFields(_ index: Int) -> some View {
        NumberField(title: "Mass", value: overrideBinding(index, \.mass, units.mass), unit: units.mass.symbol)
        ForEach(FrameAxis.allCases, id: \.self) { axis in
            NumberField(
                title: "COM \(axis.name)",
                value: overrideBinding(index, \.centerOfMass[axis.rawValue], units.length),
                unit: units.length.symbol
            )
        }
        let components: [(String, WritableKeyPath<MassOverride, Double>)] = [
            ("Ixx", \.inertia.xx), ("Iyy", \.inertia.yy), ("Izz", \.inertia.zz),
            ("Ixy", \.inertia.xy), ("Ixz", \.inertia.xz), ("Iyz", \.inertia.yz)
        ]
        ForEach(components, id: \.0) { name, keyPath in
            NumberField(title: name, value: overrideBinding(index, keyPath, units.inertia), unit: units.inertia.symbol)
        }
    }

    private func overrideBinding(_ index: Int, _ keyPath: WritableKeyPath<MassOverride, Double>, _ unit: some DisplayUnit) -> Binding<Double> {
        Binding {
            if case .override(let values) = document.parts[index].mass { unit.fromSI(values[keyPath: keyPath]) } else { 0 }
        } set: { value in
            guard case .override(var values) = document.parts[index].mass else { return }
            values[keyPath: keyPath] = unit.toSI(value)
            document.parts[index].mass = .override(values)
        }
    }

    // MARK: Several parts

    @ViewBuilder
    private var multipleParts: some View {
        Section("\(parts.count) Parts") {
            NumberField(title: "Mass of each", value: $massForEach, unit: units.mass.symbol)
            HStack {
                Button("Set Measured Mass") {
                    setMass(.measured(units.mass.toSI(massForEach)))
                }
                .disabled(massForEach <= 0)
                Button("Clear Mass") {
                    setMass(.unassigned)
                }
            }
        }
    }

    private func setMass(_ assignment: MassAssignment) {
        for index in document.parts.indices where partIDs.contains(document.parts[index].id) {
            document.parts[index].mass = assignment
        }
    }

    // MARK: Bodies

    @ViewBuilder
    private var bodySection: some View {
        Section("Body") {
            let memberships = Set(document.bodies.filter { !Set($0.partIDs).isDisjoint(with: partIDs) }.map(\.name))
            LabeledContent("In", value: memberships.isEmpty ? "None" : memberships.sorted().joined(separator: ", "))
            HStack {
                Button("New Body") {
                    model.createBody(in: &document)
                }
                .help("Make a body from the selected parts")
                if !document.bodies.isEmpty {
                    Menu("Add to") {
                        ForEach(document.bodies) { body in
                            Button(body.name) { add(to: body.id) }
                        }
                    }
                    .fixedSize()
                }
                if !memberships.isEmpty {
                    Button("Remove") {
                        model.removeFromBodies(partIDs, in: &document)
                    }
                }
            }
        }
    }

    private func add(to bodyID: UUID) {
        model.removeFromBodies(partIDs, in: &document)
        guard let index = document.bodies.firstIndex(where: { $0.id == bodyID }) else { return }
        document.bodies[index].partIDs += document.parts.map(\.id).filter(partIDs.contains)
    }
}
