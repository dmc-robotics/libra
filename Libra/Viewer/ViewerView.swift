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
        view.upAxis = upAxis
        view.wantsHover = wantsHover
        view.scene = scene
    }
}
