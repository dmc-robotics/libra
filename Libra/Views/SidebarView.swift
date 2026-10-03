import LibraKit
import SwiftUI

struct SidebarView: View {
    @Binding var document: LibraDocument
    @Bindable var model: DocumentModel

    var body: some View {
        List(selection: $model.selection) {
            Section("Parts") {
                ForEach(DocumentModel.outline(for: document.parts)) { node in
                    OutlineRow(node: node, document: $document, model: model)
                }
            }
            Section("Groups") {
                ForEach(document.groups) { group in
                    GroupRow(group: group, document: $document, model: model)
                        .tag(SidebarItem.group(group.id))
                }
                if document.groups.isEmpty {
                    Text("Select parts, then ⌘G")
                        .foregroundStyle(.secondary)
                        .help("Edit › New Group from Selection")
                        .selectionDisabled()
                }
            }
        }
        .contextMenu(forSelectionType: SidebarItem.self) { items in
            // Parts and assemblies get the same menu as parts in the viewer
            let partIDs = model.partIDs(of: items.filter { if case .group = $0 { false } else { true } }, in: document)
            if !partIDs.isEmpty {
                ForEach(model.partMenu(in: document)) { item in
                    if let command = item.command {
                        Button(item.title) {
                            model.perform(command, on: partIDs, in: &document)
                        }
                    } else {
                        Menu(item.title) {
                            ForEach(item.children) { child in
                                Button(child.title) {
                                    if let command = child.command {
                                        model.perform(command, on: partIDs, in: &document)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if items.count == 1, case .group(let id) = items.first {
                Button("Select Parts") {
                    model.selectParts(ofGroup: id, in: document)
                }
                Button("Rename") {
                    model.renamingGroupID = id
                }
                Divider()
                Button("Delete Group", role: .destructive) {
                    model.deleteGroup(id, in: &document)
                }
            }
        } primaryAction: { items in
            model.primaryAction(on: items)
        }
    }
}

/// An assembly or part in the outline. Assemblies open and close like OutlineGroup rows, but the model remembers which are open.
private struct OutlineRow: View {
    let node: OutlineNode
    @Binding var document: LibraDocument
    let model: DocumentModel

    var body: some View {
        if case .assembly(let path) = node.id {
            DisclosureGroup(isExpanded: isExpanded(path)) {
                ForEach(node.children ?? []) { child in
                    OutlineRow(node: child, document: $document, model: model)
                }
            } label: {
                let partIDs = model.partIDs(of: [node.id], in: document)
                HStack {
                    Label(node.name, systemImage: "square.stack.3d.up")
                    Spacer()
                    VisibilityToggle(isHidden: document.areAllHidden(partIDs)) { document.setHidden($0, forParts: partIDs) }
                    MassStatusIcon(parts: document.parts(partIDs))
                }
            }
            .tag(node.id)
        } else if case .part(let id) = node.id, let part = document.part(id) {
            HStack {
                Label(node.name, systemImage: "cube")
                Spacer()
                VisibilityToggle(isHidden: part.isHidden) { document.setHidden($0, forParts: [id]) }
                MassStatusIcon(part: part)
            }
            .tag(node.id)
        }
    }

    private func isExpanded(_ path: [String]) -> Binding<Bool> {
        Binding {
            model.expandedAssemblies.contains(path)
        } set: {
            model.setAssembly(path, expanded: $0)
        }
    }
}

/// A group in the sidebar. Double-click or Rename edits its name in place: Return or clicking away
/// keeps the new name, Escape cancels.
private struct GroupRow: View {
    let group: PartGroup
    @Binding var document: LibraDocument
    @Bindable var model: DocumentModel
    @State private var draftName = ""
    @FocusState private var isNameFocused: Bool

    private var isRenaming: Bool { model.renamingGroupID == group.id }

    var body: some View {
        HStack {
            if isRenaming {
                Label {
                    TextField("Name", text: $draftName)
                        .focused($isNameFocused)
                        .onSubmit { model.finishRenaming(group.id, to: draftName, in: &document) }
                        .onExitCommand { model.renamingGroupID = nil }
                        .onChange(of: isNameFocused) { _, isFocused in
                            if !isFocused && isRenaming {
                                model.finishRenaming(group.id, to: draftName, in: &document)
                            }
                        }
                        .task {
                            draftName = group.name
                            isNameFocused = true
                        }
                } icon: {
                    Image(systemName: "cube.fill")
                }
            } else {
                Label(group.name, systemImage: "cube.fill")
            }
            Spacer()
            FrameVisibilityToggle(target: .group(group.id), document: $document)
            VisibilityToggle(isHidden: document.areAllHidden(group.partIDs)) {
                document.setHidden($0, forParts: Set(group.partIDs))
            }
        }
        .badge(group.partIDs.count)
    }
}

/// Shows or hides parts in the viewer: an eye, struck through while hidden.
struct VisibilityToggle: View {
    let isHidden: Bool
    let setHidden: (Bool) -> Void

    var body: some View {
        Button {
            setHidden(!isHidden)
        } label: {
            Image(systemName: isHidden ? "eye.slash" : "eye")
                .foregroundStyle(isHidden ? HierarchicalShapeStyle.tertiary : .secondary)
        }
        .buttonStyle(.borderless)
        .imageScale(.small)
        .help(isHidden ? "Show in the viewer" : "Hide in the viewer")
    }
}

/// Shows or hides a group's coordinate system in the viewer.
struct FrameVisibilityToggle: View {
    let target: FrameTarget
    @Binding var document: LibraDocument

    var body: some View {
        let shows = document.showsFrame(target)
        Button {
            document.setShowsFrame(!shows, for: target)
        } label: {
            Image(systemName: "move.3d")
                .foregroundStyle(shows ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
        }
        .buttonStyle(.borderless)
        .imageScale(.small)
        .help(shows ? "Hide coordinate system" : "Show coordinate system")
    }
}

/// A quiet trailing mark for a part's mass: hollow until assigned, a warning only when something is wrong.
struct MassStatusIcon: View {
    enum Status {
        case missing, noVolume, assigned
    }

    let status: Status
    let help: String

    init(part: Part) {
        if part.mass <= 0 {
            status = .missing
            help = "No mass yet"
        } else if !part.hasVolume {
            status = .noVolume
            help = "This part has no volume, so its mass can't be spread through it and is left out."
        } else {
            status = .assigned
            help = "Mass assigned"
        }
    }

    /// An assembly: done once every part counts toward the mass.
    init(parts: [Part]) {
        if parts.allSatisfy({ $0.massProperties != nil }) {
            status = .assigned
            help = "Every part has a mass"
        } else {
            status = .missing
            help = "Not every part has a mass yet"
        }
    }

    var body: some View {
        Group {
            switch status {
            case .missing:
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.tertiary)
            case .noVolume:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .assigned:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .help(help)
        .imageScale(.small)
    }
}
