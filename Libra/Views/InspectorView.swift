import LibraKit
import SwiftUI

/// Shows whatever is selected: one group, some parts, or (with nothing selected) the Libra frame.
struct InspectorView: View {
    @Binding var document: LibraDocument
    @Bindable var model: DocumentModel

    var body: some View {
        Form {
            if let group = model.selectedGroup(in: document) {
                GroupInspector(groupID: group.id, document: $document, model: model)
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
            Text("The reference for totals, views and export, usually the robot's base with Z up. In STEP file coordinates.")
        }
        MassPropertiesSection(summary: MassSummary(parts: document.parts).expressed(in: document.libraFrame), frameName: "Libra frame")
    }
}

// MARK: Groups

private struct GroupInspector: View {
    let groupID: UUID
    @Binding var document: LibraDocument
    @Bindable var model: DocumentModel

    private var index: Int? {
        document.groups.firstIndex { $0.id == groupID }
    }

    var body: some View {
        if let index {
            let group = document.groups[index]
            let summary = MassSummary(parts: document.parts(group.partIDs))
            Section("Group") {
                TextField("Name", text: $document.groups[index].name)
                LabeledContent("Parts") {
                    HStack {
                        Text("\(summary.partCount)")
                        Button("Select") {
                            model.selection = Set(group.partIDs.map(SidebarItem.part))
                        }
                        .help("Select this group's parts")
                    }
                }
            }
            Section {
                FrameEditor(target: .group(groupID), document: $document, model: model)
            } header: {
                Text("Group Frame")
            } footer: {
                Text("Relative to the Libra frame.")
            }
            MassPropertiesSection(summary: summary.expressed(in: group.frame), frameName: "group frame")
            Section {
                Button("Delete Group", role: .destructive) {
                    model.deleteGroup(groupID, in: &document)
                }
            }
        }
    }
}

// MARK: Parts

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
        groupSection
        MassPropertiesSection(summary: MassSummary(parts: parts).expressed(in: document.libraFrame), frameName: "Libra frame")
    }

    // MARK: One part

    @ViewBuilder
    private func singlePart(_ part: Part, index: Int) -> some View {
        Section("Part") {
            LabeledContent("Name", value: part.name)
            LabeledContent("Component", value: part.definitionName)
            if !part.path.isEmpty {
                LabeledContent("Assembly", value: part.path.joined(separator: " › "))
            }
            LabeledContent("Volume") {
                Text("\(Formatting.number(part.volumeProperties.volume / pow(units.length.siPerUnit, 3))) \(units.length.symbol)³")
            }
            if !part.hasVolume {
                Label("No closed volume (a surface body?), so its mass is left out.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        Section("Mass") {
            NumberField(title: "Mass", value: massBinding(index), unit: units.mass.symbol)
            if part.hasVolume && part.mass > 0 {
                // g/cm³ is a handy sanity check against the material
                LabeledContent("Density", value: "\(Formatting.number(part.mass / part.volumeProperties.volume / 1000)) g/cm³")
            }
        }
    }

    private func massBinding(_ index: Int) -> Binding<Double> {
        Binding {
            units.mass.fromSI(document.parts[index].mass)
        } set: {
            document.parts[index].mass = max(0, units.mass.toSI($0))
        }
    }

    // MARK: Several parts

    @ViewBuilder
    private var multipleParts: some View {
        Section {
            NumberField(title: "Mass of Each", value: $massForEach, unit: units.mass.symbol)
            HStack {
                Spacer()
                Button("Clear") {
                    document.setMass(0, forParts: partIDs)
                }
                .help("Remove the mass from all \(parts.count) parts")
                Button("Apply") {
                    document.setMass(units.mass.toSI(massForEach), forParts: partIDs)
                }
                .disabled(massForEach <= 0)
                .help("Give each of the \(parts.count) parts this mass")
            }
        } header: {
            Text("Mass of \(parts.count) Parts")
        }
    }

    // MARK: Groups

    private enum GroupChoice: Hashable {
        case none, mixed, new
        case group(UUID)
    }

    private var groupSection: some View {
        Section {
            Picker("Group", selection: groupChoice) {
                Text("None").tag(GroupChoice.none)
                ForEach(document.groups) { group in
                    Text(group.name).tag(GroupChoice.group(group.id))
                }
                if groupChoice.wrappedValue == .mixed {
                    Text("Multiple").tag(GroupChoice.mixed)
                }
                Divider()
                Text("New Group").tag(GroupChoice.new)
            }
            .help("The group these parts belong to, which moves as one rigid body")
        }
    }

    private var groupChoice: Binding<GroupChoice> {
        Binding {
            let groups = Set(partIDs.map { document.group(containing: $0)?.id })
            guard groups.count == 1, let only = groups.first else { return .mixed }
            return only.map(GroupChoice.group) ?? .none
        } set: { choice in
            switch choice {
            case .none: document.removeFromGroups(partIDs)
            case .group(let id): document.addParts(partIDs, toGroup: id)
            case .new: model.createGroup(in: &document)
            case .mixed: break
            }
        }
    }
}
