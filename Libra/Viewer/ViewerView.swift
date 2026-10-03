import LibraKit
import SwiftUI

/// SwiftUI wrapper for the Metal viewer. The app only talks to the viewer through this and `ViewerScene`.
struct ViewerView: NSViewRepresentable {
    let scene: ViewerScene
    let upAxis: SIMD3<Double>
    let wantsHover: Bool
    let controller: ViewerController
    let pick: (Ray) -> PickHit?
    let onHover: (ViewerPointer?) -> Void
    let onClick: (ViewerPointer, Bool) -> Void
    let onKey: (String, Bool) -> Bool
    let contextMenu: (ViewerPointer) -> [ViewerMenuItem]

    func makeNSView(context: Context) -> ViewerMTKView {
        let view = ViewerMTKView()
        controller.view = view
        return view
    }

    func updateNSView(_ view: ViewerMTKView, context: Context) {
        view.pick = pick
        view.onHover = onHover
        view.onClick = onClick
        view.onKey = onKey
        view.contextMenu = contextMenu
        view.upAxis = upAxis
        view.wantsHover = wantsHover
        view.scene = scene
    }
}

/// One command in the viewer's right-click menu, or a submenu of them.
struct ViewerMenuItem {
    var title: String
    var action: (() -> Void)?
    var children: [ViewerMenuItem] = []
}
