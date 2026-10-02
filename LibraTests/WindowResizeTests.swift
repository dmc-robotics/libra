import AppKit
@testable import Libra
import LibraKit
import SwiftUI
import Testing

/// Shrinking the document window used to crash with an AppKit "too many Update Constraints passes"
/// exception when the window got narrower than the split view's columns could fit.
@MainActor
@Suite struct WindowResizeTests {
    @Test func shrinkingTheWindowSettles() {
        let document = LibraFileDocument(content: DocumentModelTests.makeDocument())
        let root = DocumentView(document: .constant(document), fileURL: nil)
            .frame(minWidth: Layout.windowMinWidth, minHeight: Layout.windowMinHeight)
        let controller = NSHostingController(rootView: root)
        // Like a document window: toolbar items bridged into a unified toolbar, content under the title bar
        controller.sceneBridgingOptions = .all
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: Layout.defaultWindowWidth, height: Layout.defaultWindowHeight))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        settle()

        // Down to the narrowest the window allows, as when dragging its edge
        for width in stride(from: Layout.defaultWindowWidth, through: Layout.windowMinWidth, by: -10) {
            window.setContentSize(NSSize(width: width, height: Layout.windowMinHeight))
            // Let AppKit's display cycle run, which is where the constraint passes happen
            settle()
        }
        #expect(window.contentView != nil)
    }

    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
}
