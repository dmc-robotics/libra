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
            if items.contains(where: { if case .group = $0 { false } else { true } }) {
                Button("New Group from Selection") {
                    model.createGroup(from: items, in: &document)
                }
            }
            if items.count == 1, case .group(let id) = items.first {
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
                if case .override = part.mass {
                    FrameVisibilityToggle(target: .override(id), document: $document)
                }
                MassStatusIcon(part: part)
            }
        } else {
            Label(node.name, systemImage: "square.stack.3d.up")
        }
    }
}

/// Shows or hides a group's or part's coordinate system in the viewer.
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
            switch part.mass {
            case .unassigned:
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.tertiary)
                    .help("No mass yet")
            case .measured where !part.hasVolume:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("This part has no volume, so a measured mass can't be spread through it. Use an override.")
            case .measured:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("Measured mass")
            case .override:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .help("Override values")
            }
        }
        .imageScale(.small)
    }
}
