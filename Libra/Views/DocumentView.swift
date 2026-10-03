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
        .focusedSceneValue(\.documentActions, actions)
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

    /// Menu bar commands for this window.
    private var actions: DocumentActions {
        let isEmpty = document.content.isEmpty
        let selectedGroup = model.selectedGroup(in: document.content)
        let hasSelectedParts = !model.selectedPartIDs(in: document.content).isEmpty
        return DocumentActions(
            importStep: isEmpty && !model.isImporting ? { isImporterPresented = true } : nil,
            export: isEmpty ? nil : { model.isShowingExport = true },
            fit: { model.viewer.fit() },
            look: { model.viewer.look(from: $0, in: document.content.libraFrame) },
            colorMode: $model.colorMode,
            newGroup: hasSelectedParts && selectedGroup == nil ? { model.createGroup(in: &document.content) } : nil,
            deleteGroup: selectedGroup.map { group in { model.deleteGroup(group.id, in: &document.content) } }
        )
    }

    // MARK: Empty document

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Model", systemImage: "cube.transparent")
        } description: {
            Text("Import a STEP assembly to start. In Fusion, use File › Export and choose STEP.")
        } actions: {
            if model.isImporting {
                ProgressView("Importing…")
            } else {
                Button("Import STEP File…") { isImporterPresented = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
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
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    StatusBar(document: $document.content, model: model)
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
            onKey: { characters, shift in model.handleKey(characters, shift: shift, in: &document.content) },
            contextMenu: viewerMenu
        )
    }

    private func viewerMenu(for pointer: ViewerPointer) -> [ViewerMenuItem] {
        guard let partIDs = model.contextMenuPartIDs(for: pointer, in: document.content) else { return [] }
        return [
            ViewerMenuItem(title: "Select Others") { model.selectOthers(like: partIDs, in: document.content) }
        ]
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                ForEach(StandardView.allCases, id: \.self) { view in
                    Button(view.name) { model.viewer.look(from: view, in: document.content.libraFrame) }
                }
            } label: {
                Label("Standard View", systemImage: "cube")
            }
            .help("Look from a standard direction, relative to the Libra frame")
            Button {
                model.viewer.fit()
            } label: {
                Label("Zoom to Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .help("Fit the model in the view")
            Menu {
                Picker("Color By", selection: $model.colorMode) {
                    ForEach(ColorMode.allCases) { mode in
                        Text(mode.name).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Color By", systemImage: "paintpalette")
            }
            .help("Color parts by their CAD color, mass status or group")
        }
        ToolbarItem {
            Button {
                model.isShowingExport = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export mass properties as JSON, CSV, MJCF or URDF")
        }
        ToolbarItem {
            Button {
                isInspectorPresented.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help("Show or hide the inspector")
        }
    }
}
