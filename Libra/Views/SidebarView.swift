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
                    Label {
                        Text(body.name)
                        Text("\(body.partIDs.count) parts").foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "cube.fill")
                    }
                    .tag(SidebarItem.body(body.id))
                }
                if document.bodies.isEmpty {
                    Text("Select parts, then choose New Body from the context menu or inspector")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            Label {
                Text(node.name)
            } icon: {
                MassStatusIcon(part: part)
            }
        } else {
            Label(node.name, systemImage: "shippingbox")
        }
    }
}

struct MassStatusIcon: View {
    let part: Part

    var body: some View {
        switch part.mass {
        case .unassigned:
            Image(systemName: "circle.dashed")
                .foregroundStyle(.orange)
                .help("No mass assigned")
        case .measured where !part.hasVolume:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help("This part has no volume, so a measured mass can't be spread through it. Use an override.")
        case .measured:
            Image(systemName: "scalemass.fill")
                .foregroundStyle(.green)
                .help("Measured mass")
        case .override:
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.blue)
                .help("Override values")
        }
    }
}
