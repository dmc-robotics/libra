import LibraKit
import SwiftUI

struct SidebarView: View {
    @Binding var document: LibraDocument
    @Bindable var model: DocumentModel

    var body: some View {
        List(selection: $model.selection) {
            Section("Parts") {
                OutlineGroup(DocumentModel.outline(for: document.parts), children: \.children) { node in
                    row(for: node)
                        .tag(node.id)
                }
            }
            Section("Groups") {
                ForEach(document.groups) { group in
                    HStack {
                        Label(group.name, systemImage: "cube.fill")
                        Spacer()
                        FrameVisibilityToggle(target: .group(group.id), document: $document)
                    }
                    .badge(group.partIDs.count)
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
                Divider()
                Button("Delete Group", role: .destructive) {
                    model.deleteGroup(id, in: &document)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for node: OutlineNode) -> some View {
        if case .part(let id) = node.id, let part = document.part(id) {
            HStack {
                Label(node.name, systemImage: "cube")
                Spacer()
                MassStatusIcon(part: part)
            }
        } else {
            Label(node.name, systemImage: "square.stack.3d.up")
        }
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
    let part: Part

    var body: some View {
        Group {
            if part.mass <= 0 {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.tertiary)
                    .help("No mass yet")
            } else if !part.hasVolume {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("This part has no volume, so its mass can't be spread through it and is left out.")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("Mass assigned")
            }
        }
        .imageScale(.small)
    }
}
