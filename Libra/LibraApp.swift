import SwiftUI

@main
struct LibraApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: LibraFileDocument()) { configuration in
            DocumentView(document: configuration.$document, fileURL: configuration.fileURL)
                .frame(minWidth: Layout.windowMinWidth, minHeight: Layout.windowMinHeight)
        }
        .defaultSize(width: Layout.defaultWindowWidth, height: Layout.defaultWindowHeight)
        .commands {
            SidebarCommands()
            InspectorCommands()
            LibraCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
