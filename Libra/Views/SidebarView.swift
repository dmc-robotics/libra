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
            Section("Bodies") {
                ForEach(document.bodies) { body in
                    Label(body.name, systemImage: "cube.fill")
                        .badge(body.partIDs.count)
                        .tag(SidebarItem.body(body.id))
                }
                if document.bodies.isEmpty {
                    Text("Select parts, then ⌘G")
                        .foregroundStyle(.secondary)
                        .help("Edit › New Body from Selection")
                        .selectionDisabled()
                }
            }
        }
        .contextMenu(forSelectionType: SidebarItem.self) { items in
            if items.contains(where: { if case .body = $0 { false } else { true } }) {
                Button("New Body from Selection") {
                    model.createBody(from: items, in: &document)
                }
            }
            if items.count == 1, case .body(let id) = items.first {
                Button("Delete Body", role: .destructive) {
                    model.deleteBody(id, in: &document)
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
