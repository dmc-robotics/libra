import AppKit
@testable import Libra
import LibraKit
import SwiftUI
import Testing

/// Shrinking the document window used to crash with an AppKit "too many Update Constraints passes"
/// exception: the window could get narrower than the split view's columns needed, and the status bar's
/// text raised the viewer column's minimum. Both are covered: the test fails if either comes back.
@MainActor
@Suite struct WindowResizeTests {
    @Test func shrinkingTheWindowSettles() {
        // Masses make the status bar and the inspector's mass section show long numbers
        var content = DocumentModelTests.makeDocument()
        content.setMass(0.123456, forParts: Set(content.parts.map(\.id)))
        let document = LibraFileDocument(content: content)
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
