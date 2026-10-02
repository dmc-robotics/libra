import Foundation
import LibraKit
import Observation
import StepImport
import simd

enum SidebarItem: Hashable {
    case part(UUID)
    /// An assembly node, identified by its path of names from the root.
    case assembly([String])
    case body(UUID)
}

/// A frame the frame tool can edit.
enum FrameTarget: Hashable {
    case libra
    case body(UUID)
    /// The frame a part's override values are entered in.
    case override(UUID)
}

enum Tool: Hashable {
    case select
    case pickOrigin(FrameTarget)
    case pickDirection(FrameTarget, FrameAxis)

    var target: FrameTarget? {
        switch self {
        case .select: nil
        case .pickOrigin(let target), .pickDirection(let target, _): target
        }
    }
}

enum ColorMode: String, CaseIterable, Identifiable {
    case cad, massStatus, body

    var id: Self { self }

    var name: String {
        switch self {
        case .cad: "CAD Colors"
        case .massStatus: "Mass Status"
        case .body: "Bodies"
        }
    }
}

/// What the viewer reports about the cursor.
struct ViewerPointer {
    var hit: PickHit?
    var camera: OrthographicCamera
    var cursor: SIMD2<Double>
}

/// A row in the sidebar's assembly outline.
struct OutlineNode: Identifiable, Hashable {
    var id: SidebarItem
    var name: String
    var children: [OutlineNode]?
}

/// Per-window UI state: selection, tools and hover. Document data stays in the FileDocument and is passed in.
@MainActor @Observable
final class DocumentModel {
    var selection: Set<SidebarItem> = []
    var tool: Tool = .select {
        didSet { hoverSnap = nil }
    }
    var hoverSnap: Snap?
    var colorMode: ColorMode = .cad
    var isImporting = false
    var errorMessage: String?
    var isShowingExport = false

    @ObservationIgnored let viewer = ViewerController()
    @ObservationIgnored private var picker = PartPicker(parts: [])

    // MARK: Selection

    func selectedPartIDs(in document: LibraDocument) -> Set<UUID> {
        var ids: Set<UUID> = []
        for item in selection {
            switch item {
            case .part(let id):
                ids.insert(id)
            case .assembly(let path):
                for part in document.parts where part.path.starts(with: path) {
                    ids.insert(part.id)
                }
            case .body(let id):
                ids.formUnion(document.bodies.first { $0.id == id }?.partIDs ?? [])
            }
        }
        return ids
    }

    /// The body, when exactly one body is selected.
    func selectedBody(in document: LibraDocument) -> Body? {
        guard selection.count == 1, case .body(let id) = selection.first else { return nil }
        return document.bodies.first { $0.id == id }
    }

    static func outline(for parts: [Part]) -> [OutlineNode] {
        final class Builder {
            let name: String
            let path: [String]
            var children: [Builder] = []
            var parts: [Part] = []

            init(name: String, path: [String]) {
                self.name = name
                self.path = path
            }

            func child(named name: String) -> Builder {
                if let existing = children.first(where: { $0.name == name }) {
                    return existing
                }
                let child = Builder(name: name, path: path + [name])
                children.append(child)
                return child
            }

            var nodes: [OutlineNode] {
                children.map { OutlineNode(id: .assembly($0.path), name: $0.name, children: $0.nodes) }
                    + parts.map { OutlineNode(id: .part($0.id), name: $0.name, children: nil) }
            }
        }
        let root = Builder(name: "", path: [])
        for part in parts {
            part.path.reduce(root) { $0.child(named: $1) }.parts.append(part)
        }
        return root.nodes
    }

    // MARK: Frames

    func frame(for target: FrameTarget, in document: LibraDocument) -> Frame? {
        switch target {
        case .libra:
            document.libraFrame
        case .body(let id):
            document.bodies.first { $0.id == id }?.frame
        case .override(let id):
            if case .override(let values) = document.part(id)?.mass { values.frame } else { nil }
        }
    }

    func setFrame(_ frame: Frame, for target: FrameTarget, in document: inout LibraDocument) {
        switch target {
        case .libra:
            document.libraFrame = frame
        case .body(let id):
            guard let index = document.bodies.firstIndex(where: { $0.id == id }) else { return }
            document.bodies[index].frame = frame
        case .override(let id):
            guard let index = document.parts.firstIndex(where: { $0.id == id }),
                  case .override(var values) = document.parts[index].mass else { return }
            values.frame = frame
            document.parts[index].mass = .override(values)
        }
    }

    // MARK: Viewer input

    private func syncPicker(with document: LibraDocument) {
        if picker.partIDs != document.parts.map(\.id) {
            picker = PartPicker(parts: document.parts)
        }
    }

    func pick(_ ray: Ray, in document: LibraDocument) -> PickHit? {
        syncPicker(with: document)
        return picker.pick(ray)
    }

    private func snap(for pointer: ViewerPointer, in document: LibraDocument) -> Snap? {
        guard let hit = pointer.hit, let part = document.part(hit.partID) else { return nil }
        let snapper = Snapper(camera: pointer.camera, cursor: pointer.cursor)
        switch tool {
        case .select: return nil
        case .pickOrigin: return snapper.originSnap(for: hit, in: part.geometry)
        case .pickDirection: return snapper.directionSnap(for: hit, in: part.geometry)
        }
    }

    func hover(_ pointer: ViewerPointer?, in document: LibraDocument) {
        let snap = pointer.flatMap { snap(for: $0, in: document) }
        if snap != hoverSnap {
            hoverSnap = snap
        }
    }

    func click(_ pointer: ViewerPointer, extendingSelection: Bool, in document: inout LibraDocument) {
        switch tool {
        case .select:
            guard let hit = pointer.hit else {
                if !extendingSelection { selection = [] }
                return
            }
            let item = SidebarItem.part(hit.partID)
            if extendingSelection {
                if selection.contains(item) { selection.remove(item) } else { selection.insert(item) }
            } else {
                selection = [item]
            }
        case .pickOrigin(let target):
            guard let snap = snap(for: pointer, in: document), let frame = frame(for: target, in: document) else { return }
            setFrame(frame.moved(to: snap.point), for: target, in: &document)
            tool = .select
        case .pickDirection(let target, let axis):
            guard let snap = snap(for: pointer, in: document), var direction = snap.direction,
                  let frame = frame(for: target, in: document) else { return }
            // Feature directions have no meaningful sign, so keep the one nearest the axis' current direction
            if simd_dot(direction, frame.axis(axis)) < 0 {
                direction = -direction
            }
            setFrame(frame.aligning(axis, to: direction), for: target, in: &document)
            tool = .select
        }
    }

    /// Keys while the viewer has focus: Escape cancels a pick; X, Y, Z turn the frame being edited
    /// a quarter (Shift turns the other way).
    func handleKey(_ characters: String, shift: Bool, in document: inout LibraDocument) -> Bool {
        if characters == "\u{1b}" {
            guard tool != .select else { return false }
            tool = .select
            return true
        }
        guard let target = activeFrameTarget(in: document), let frame = frame(for: target, in: document) else { return false }
        let axis: FrameAxis? = switch characters.lowercased() {
        case "x": .x
        case "y": .y
        case "z": .z
        default: nil
        }
        guard let axis else { return false }
        setFrame(frame.rotatedQuarterTurn(about: axis, clockwise: shift), for: target, in: &document)
        return true
    }

    /// The frame the inspector is editing: the picking tool's target, else the selected body's, else the Libra frame.
    func activeFrameTarget(in document: LibraDocument) -> FrameTarget? {
        if let target = tool.target { return target }
        if let body = selectedBody(in: document) { return .body(body.id) }
        if selection.isEmpty { return .libra }
        return nil
    }

    // MARK: Bodies

    /// Makes a body from the selected parts, taking them out of any other body.
    func createBody(in document: inout LibraDocument) {
        let partIDs = document.parts.map(\.id).filter(selectedPartIDs(in: document).contains)
        guard !partIDs.isEmpty else { return }
        removeFromBodies(Set(partIDs), in: &document)
        let body = Body(name: "Body \(document.bodies.count + 1)", partIDs: partIDs, frame: document.libraFrame)
        document.bodies.append(body)
        selection = [.body(body.id)]
    }

    func removeFromBodies(_ partIDs: Set<UUID>, in document: inout LibraDocument) {
        for index in document.bodies.indices {
            document.bodies[index].partIDs.removeAll(where: partIDs.contains)
        }
    }

    func deleteBody(_ id: UUID, in document: inout LibraDocument) {
        document.bodies.removeAll { $0.id == id }
        selection.remove(.body(id))
    }

    // MARK: Import

    func importStep(from url: URL) async -> LibraDocument? {
        isImporting = true
        defer { isImporting = false }
        do {
            let parts = try await StepImporter.shared.importParts(from: url)
            selection = []
            tool = .select
            return LibraDocument(parts: parts)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: Scene

    func scene(for document: LibraDocument, highlightColor: SIMD4<Float>) -> ViewerScene {
        let selectedIDs = selectedPartIDs(in: document)
        let bodyIndexByPart = Dictionary(
            document.bodies.enumerated().flatMap { index, body in body.partIDs.map { ($0, index) } },
            uniquingKeysWith: { first, _ in first }
        )
        let parts = document.parts.map { part in
            var color: SIMD4<Float> = switch colorMode {
            case .cad:
                part.color.map { SIMD4($0.red, $0.green, $0.blue, 1) } ?? ViewerStyle.defaultPartColor
            case .massStatus:
                part.massProperties == nil ? ViewerStyle.unassignedColor : ViewerStyle.assignedColor
            case .body:
                bodyIndexByPart[part.id].map { ViewerStyle.bodyColors[$0 % ViewerStyle.bodyColors.count] } ?? ViewerStyle.unbodiedColor
            }
            if selectedIDs.contains(part.id) {
                color = simd_mix(color, highlightColor, SIMD4(repeating: ViewerStyle.selectionTint))
            }
            return ViewerPart(id: part.id, geometry: part.geometry, color: color)
        }

        var markers: [Marker] = []
        let target = activeFrameTarget(in: document)
        markers.append(.triad(document.libraFrame, emphasized: target == .libra))
        if let target, target != .libra, let frame = frame(for: target, in: document) {
            markers.append(.triad(frame, emphasized: true))
        }
        let summary = MassSummary(parts: selectedIDs.isEmpty ? document.parts : document.parts(selectedIDs))
        if summary.properties.mass > 0 {
            markers.append(.centerOfMass(summary.properties.centerOfMass))
        }
        if let hoverSnap {
            if let edge = hoverSnap.edge, let part = document.part(edge.partID) {
                markers.append(.snapEdge(part.geometry.points(ofEdge: edge.index).map(SIMD3<Double>.init)))
            }
            if let direction = hoverSnap.direction {
                markers.append(.snapDirection(origin: hoverSnap.point, direction: direction))
            } else {
                markers.append(.snapPoint(hoverSnap.point))
            }
        }
        return ViewerScene(
            parts: parts,
            highlightedFace: hoverSnap?.edge == nil ? hoverSnap?.face : nil,
            highlightColor: highlightColor,
            markers: markers
        )
    }
}

/// Lets the window's toolbar drive the viewer's camera.
@MainActor
final class ViewerController {
    weak var view: ViewerMTKView?

    func fit() {
        view?.fitToScene()
    }

    func look(from standardView: StandardView, in frame: Frame) {
        view?.look(from: standardView, in: frame)
    }
}
