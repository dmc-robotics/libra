import LibraKit
import SwiftUI

/// What the menu bar can do in the focused document window. Absent when no document has focus;
/// an action is nil when it doesn't apply right now.
struct DocumentActions {
    var importStep: (() -> Void)?
    var export: (() -> Void)?
    var fit: () -> Void
    var look: (StandardView) -> Void
    var colorMode: Binding<ColorMode>
    var newBody: (() -> Void)?
    var deleteBody: (() -> Void)?
}

extension FocusedValues {
    @Entry var documentActions: DocumentActions?
}

struct LibraCommands: Commands {
    @FocusedValue(\.documentActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Button("Import STEP File…") { actions?.importStep?() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(actions?.importStep == nil)
            Button("Export Mass Properties…") { actions?.export?() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(actions?.export == nil)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("New Body from Selection") { actions?.newBody?() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(actions?.newBody == nil)
            Button("Delete Body") { actions?.deleteBody?() }
                .disabled(actions?.deleteBody == nil)
        }
        CommandGroup(before: .toolbar) {
            Button("Zoom to Fit") { actions?.fit() }
                .keyboardShortcut("9", modifiers: .command)
                .disabled(actions == nil)
            Menu("Standard View") {
                ForEach(Array(StandardView.allCases.enumerated()), id: \.element) { index, view in
                    Button(view.name) { actions?.look(view) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
            .disabled(actions == nil)
            if let colorMode = actions?.colorMode {
                Picker("Color By", selection: colorMode) {
                    ForEach(ColorMode.allCases) { mode in
                        Text(mode.name).tag(mode)
                    }
                }
            }
            Divider()
        }
    }
}
