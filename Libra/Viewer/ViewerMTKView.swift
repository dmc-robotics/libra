import AppKit
import LibraKit
import MetalKit

/// The 3D view. Owns the camera and turns mouse, trackpad and key input into camera moves or callbacks.
///
/// - Drag: orbit around the point under the cursor
/// - Right-drag, ⌥-drag or two-finger scroll: pan
/// - Pinch or mouse wheel: zoom at the cursor
/// - Double-click: fit
/// - Right-click (without dragging) or ⌃-click: context menu
final class ViewerMTKView: MTKView {
    private(set) var camera = OrthographicCamera()
    var scene = ViewerScene() {
        didSet { sceneDidChange(from: oldValue) }
    }
    /// Orbiting turns about this axis (the Libra frame's Z).
    var upAxis: SIMD3<Double> = [0, 0, 1]
    /// Hover callbacks only fire when something (the frame tool) wants them, since each one is a pick.
    var wantsHover = false
    var pick: ((Ray) -> PickHit?)?
    var onHover: ((ViewerPointer?) -> Void)?
    var onClick: ((ViewerPointer, _ extendingSelection: Bool) -> Void)?
    var onKey: ((_ characters: String, _ shift: Bool) -> Bool)?
    /// The items for a right-click at the pointer; no menu if empty.
    var contextMenu: ((ViewerPointer) -> [ViewerMenuItem])?

    private var renderer: Renderer?
    private var sceneBounds = BoundingBox.empty
    private var dragStart: SIMD2<Double>?
    private var lastDragPoint: SIMD2<Double>?
    private var isDragging = false
    private var isPanning = false
    private var orbitPivot: SIMD3<Double> = .zero
    /// The first fit waits until the view has been laid out at its real size.
    private var needsInitialFit = false

    init() {
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        colorPixelFormat = .bgra8Unorm
        depthStencilPixelFormat = .depth32Float
        sampleCount = ViewerStyle.sampleCount
        // Draw only when something changes
        isPaused = true
        enableSetNeedsDisplay = true
        renderer = Renderer(view: self)
        delegate = renderer
        updateClearColor()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Scene and camera

    private func sceneDidChange(from oldScene: ViewerScene) {
        if scene.parts.map(\.id) != oldScene.parts.map(\.id) {
            renderer?.load(scene.parts)
            sceneBounds = scene.parts.reduce(BoundingBox.empty) { $0.union($1.geometry.bounds) }
            camera.sceneBounds = sceneBounds
            if oldScene.parts.isEmpty {
                needsInitialFit = true
                fitIfReady()
            }
        }
        needsDisplay = true
    }

    func fitToScene() {
        syncViewport()
        camera.fit(sceneBounds)
        needsDisplay = true
    }

    func look(from view: StandardView, in frame: Frame) {
        camera.look(from: view, in: frame)
        fitToScene()
    }

    private func fitIfReady() {
        guard needsInitialFit, bounds.width > 1, bounds.height > 1 else { return }
        needsInitialFit = false
        fitToScene()
    }

    private func syncViewport() {
        camera.viewportSize = SIMD2(Double(max(bounds.width, 1)), Double(max(bounds.height, 1)))
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldHeight = bounds.height
        super.setFrameSize(newSize)
        // Keep the scale (meters per point) as the window resizes, so a bigger window shows more
        if oldHeight > 1, newSize.height > 1 {
            camera.viewHeight *= Double(newSize.height / oldHeight)
        }
        syncViewport()
        fitIfReady()
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateClearColor()
        needsDisplay = true
    }

    private func updateClearColor() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let background = isDark ? ViewerStyle.darkBackground : ViewerStyle.lightBackground
        clearColor = MTLClearColor(red: background.x, green: background.y, blue: background.z, alpha: 1)
    }

    // MARK: Pointer

    private func point(of event: NSEvent) -> SIMD2<Double> {
        let location = convert(event.locationInWindow, from: nil)
        return SIMD2(Double(location.x), Double(location.y))
    }

    private func pointer(at point: SIMD2<Double>) -> ViewerPointer {
        ViewerPointer(hit: pick?(camera.ray(through: point)), camera: camera, cursor: point)
    }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        guard wantsHover, !isDragging else { return }
        onHover?(pointer(at: point(of: event)))
    }

    override func mouseExited(with event: NSEvent) {
        if wantsHover {
            onHover?(nil)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.modifierFlags.contains(.control) {
            showContextMenu(for: event)
            return
        }
        beginDrag(at: point(of: event), panning: event.modifierFlags.contains(.option))
    }

    override func rightMouseDown(with event: NSEvent) {
        beginDrag(at: point(of: event), panning: true)
    }

    override func otherMouseDown(with event: NSEvent) {
        beginDrag(at: point(of: event), panning: true)
    }

    override func mouseDragged(with event: NSEvent) {
        drag(to: point(of: event))
    }

    override func rightMouseDragged(with event: NSEvent) {
        drag(to: point(of: event))
    }

    override func otherMouseDragged(with event: NSEvent) {
        drag(to: point(of: event))
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = isDragging
        // No press began here if the mouse went down as a ⌃-click and opened the context menu
        let wasPressed = dragStart != nil
        endDrag()
        guard wasPressed, !wasDragging else { return }
        if event.clickCount == 2 {
            fitToScene()
        } else {
            let extending = !event.modifierFlags.intersection([.command, .shift]).isEmpty
            onClick?(pointer(at: point(of: event)), extending)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        let wasDragging = isDragging
        endDrag()
        if !wasDragging {
            showContextMenu(for: event)
        }
    }

    private func showContextMenu(for event: NSEvent) {
        let items = contextMenu?(pointer(at: point(of: event))) ?? []
        guard !items.isEmpty else { return }
        let menu = NSMenu()
        for item in items {
            menu.addItem(ActionMenuItem(title: item.title, action: item.action))
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func otherMouseUp(with event: NSEvent) {
        endDrag()
    }

    private func beginDrag(at point: SIMD2<Double>, panning: Bool) {
        dragStart = point
        lastDragPoint = point
        isDragging = false
        isPanning = panning
    }

    private func drag(to point: SIMD2<Double>) {
        guard let start = dragStart, let last = lastDragPoint else { return }
        if !isDragging {
            guard simd_distance(point, start) > ViewerStyle.dragThreshold else { return }
            isDragging = true
            // Orbit around what was under the cursor when the drag started, or the model's middle
            orbitPivot = pick?(camera.ray(through: start))?.point ?? (sceneBounds.isEmpty ? camera.center : sceneBounds.center)
        }
        let delta = point - last
        if isPanning {
            camera.pan(by: delta)
        } else {
            camera.orbit(by: delta, around: orbitPivot, upAxis: upAxis)
        }
        lastDragPoint = point
        needsDisplay = true
    }

    private func endDrag() {
        dragStart = nil
        lastDragPoint = nil
        isDragging = false
    }

    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas {
            // Trackpad: two-finger scroll pans
            camera.pan(by: SIMD2(Double(event.scrollingDeltaX), -Double(event.scrollingDeltaY)))
        } else {
            camera.zoom(by: exp(-Double(event.scrollingDeltaY) * ViewerStyle.wheelZoomRate), at: point(of: event))
        }
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        camera.zoom(by: 1 / (1 + Double(event.magnification)), at: point(of: event))
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        let characters = event.charactersIgnoringModifiers ?? ""
        if onKey?(characters, event.modifierFlags.contains(.shift)) != true {
            super.keyDown(with: event)
        }
    }
}

/// A menu item that runs a closure.
private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler()
    }
}
