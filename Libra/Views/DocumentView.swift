import LibraKit
import SwiftUI
import UniformTypeIdentifiers

struct DocumentView: View {
    @Binding var document: LibraFileDocument
    let fileURL: URL?
    @State private var model = DocumentModel()
    @State private var isImporterPresented = false
    @State private var isInspectorPresented = true

    private var modelName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "Libra"
    }

    var body: some View {
        Group {
            if document.content.isEmpty {
                emptyState
            } else {
                mainView
            }
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: UTType.stepFiles) { result in
            if case .success(let url) = result {
                importStep(from: url)
            }
        }
        .alert("Import Failed", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func importStep(from url: URL) {
        Task {
            if let imported = await model.importStep(from: url) {
                document.content = imported
            }
        }
    }

    // MARK: Empty document

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Import a STEP File", systemImage: "cube.transparent")
        } description: {
            Text("Libra reads an assembly's parts, names and placements. Export STEP from Fusion with File › Export.")
        } actions: {
            if model.isImporting {
                ProgressView("Importing…")
            } else {
                Button("Import STEP File…") { isImporterPresented = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, ["step", "stp"].contains(url.pathExtension.lowercased()) else { return false }
            importStep(from: url)
            return true
        }
    }

    // MARK: Document

    private var mainView: some View {
        NavigationSplitView {
            SidebarView(document: $document.content, model: model)
                .navigationSplitViewColumnWidth(min: Layout.sidebarMinWidth, ideal: Layout.sidebarIdealWidth)
        } detail: {
            viewer
                .overlay(alignment: .bottomLeading) {
                    TotalsBar(document: document.content, model: model)
                        .padding(Layout.totalsPadding)
                }
                .overlay(alignment: .top) {
                    if model.tool != .select {
                        PickingHint(tool: model.tool, snap: model.hoverSnap) { model.tool = .select }
                            .padding(Layout.totalsPadding)
                    }
                }
        }
        .inspector(isPresented: $isInspectorPresented) {
            InspectorView(document: $document.content, model: model)
                .inspectorColumnWidth(min: Layout.inspectorMinWidth, ideal: Layout.inspectorIdealWidth)
        }
        .toolbar { toolbar }
        .sheet(isPresented: $model.isShowingExport) {
            ExportSheet(report: MassReport(document: document.content, modelName: modelName), fileName: modelName)
        }
    }

    private var viewer: some View {
        ViewerView(
            scene: model.scene(for: document.content, highlightColor: NSColor.controlAccentColor.simdColor),
            upAxis: document.content.libraFrame.zAxis,
            wantsHover: model.tool != .select,
            controller: model.viewer,
            pick: { model.pick($0, in: document.content) },
            onHover: { model.hover($0, in: document.content) },
            onClick: { pointer, extending in model.click(pointer, extendingSelection: extending, in: &document.content) },
            onKey: { characters, shift in model.handleKey(characters, shift: shift, in: &document.content) }
        )
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            Menu {
                ForEach(StandardView.allCases, id: \.self) { view in
                    Button(view.name) { model.viewer.look(from: view, in: document.content.libraFrame) }
                }
            } label: {
                Label("View", systemImage: "cube")
            }
            .help("Standard views, relative to the Libra frame")
            Button {
                model.viewer.fit()
            } label: {
                Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("Fit the model in the view (or double-click it)")
            Picker("Color", selection: $model.colorMode) {
                ForEach(ColorMode.allCases) { mode in
                    Text(mode.name).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .help("How parts are colored")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.isShowingExport = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export mass properties as JSON, CSV, MJCF or URDF")
            Button {
                isInspectorPresented.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help("Show or hide the inspector")
        }
    }
}

/// Instructions shown while the frame tool waits for a click.
private struct PickingHint: View {
    let tool: Tool
    let snap: Snap?
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(snap?.kind.name ?? "Hover over a feature").foregroundStyle(.secondary)
            }
            Button("Cancel", action: cancel)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: .rect(cornerRadius: Layout.cornerRadius))
    }

    private var title: String {
        switch tool {
        case .select: ""
        case .pickOrigin: "Click a hole or shaft edge, face, or corner for the origin"
        case .pickDirection(_, let axis): "Click a shaft, face or edge to aim \(axis.name)"
        }
    }
}
