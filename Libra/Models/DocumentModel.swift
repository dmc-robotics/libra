import Foundation
import LibraKit
import Observation
import StepImport
import simd

enum SidebarItem: Hashable {
    case part(UUID)
    /// An assembly node, identified by its path of names from the root.
    case assembly([String])
    case group(UUID)
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
    case cad, massStatus, group

    var id: Self { self }

    var name: String {
        switch self {
        case .cad: "CAD Colors"
        case .massStatus: "Mass Status"
        case .group: "Groups"
        }
    }
}

/// Something the right-click menu can do to the parts it was opened on.
enum PartCommand: Hashable {
    case selectOthers
    case newGroup
    case addToGroup(UUID)
}

/// A command, or a submenu of them when `command` is nil.
struct PartMenuItem: Identifiable {
    let id = UUID()
    var title: String
    var command: PartCommand?
    var children: [PartMenuItem] = []
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
    /// The group whose name the sidebar is editing in place.
    var renamingGroupID: UUID?

    @ObservationIgnored let viewer = ViewerController()
    @ObservationIgnored private var picker = PartPicker(parts: [])

    // MARK: Selection

    func selectedPartIDs(in document: LibraDocument) -> Set<UUID> {
        partIDs(of: selection, in: document)
    }

    /// The parts that sidebar items stand for: the part itself, everything in an assembly, or a group's members.
    func partIDs(of items: Set<SidebarItem>, in document: LibraDocument) -> Set<UUID> {
        var ids: Set<UUID> = []
        for item in items {
            switch item {
            case .part(let id):
                ids.insert(id)
            case .assembly(let path):
                for part in document.parts where part.path.starts(with: path) {
                    ids.insert(part.id)
                }
            case .group(let id):
                ids.formUnion(document.group(id)?.partIDs ?? [])
            }
        }
        return ids
    }

    /// Selects every instance of the components `partIDs` are instances of, e.g. all four wheels from one.
    func selectOthers(like partIDs: Set<UUID>, in document: LibraDocument) {
        selection = Set(document.instances(sharingComponentWith: partIDs).map { .part($0.id) })
    }

    /// The parts a right-click in the viewer acts on: the selected parts if it lands on one of them, otherwise
    /// the part under the cursor, which becomes the selection. Nil off the model or while picking a frame.
    func contextMenuPartIDs(for pointer: ViewerPointer, in document: LibraDocument) -> Set<UUID>? {
        guard tool == .select, let hit = pointer.hit else { return nil }
        let selected = selectedPartIDs(in: document)
        if selected.contains(hit.partID) {
            return selected
        }
        selection = [.part(hit.partID)]
        return [hit.partID]
    }

    /// The group, when exactly one group is selected.
    func selectedGroup(in document: LibraDocument) -> PartGroup? {
        guard selection.count == 1, case .group(let id) = selection.first else { return nil }
        return document.group(id)
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
            guard let snap = snap(for: pointer, in: document), let frame = document.frame(for: target) else { return }
            document.setFrame(frame.moved(to: snap.point), for: target)
            tool = .select
        case .pickDirection(let target, let axis):
            guard let snap = snap(for: pointer, in: document), var direction = snap.direction,
                  let frame = document.frame(for: target) else { return }
            // Feature directions have no meaningful sign, so keep the one nearest the axis' current direction
            if simd_dot(direction, frame.axis(axis)) < 0 {
                direction = -direction
            }
            document.setFrame(frame.aligning(axis, to: direction), for: target)
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
        guard let target = activeFrameTarget(in: document), let frame = document.frame(for: target) else { return false }
        let axis: FrameAxis? = switch characters.lowercased() {
        case "x": .x
        case "y": .y
        case "z": .z
        default: nil
        }
        guard let axis else { return false }
        document.setFrame(frame.rotatedQuarterTurn(about: axis, clockwise: shift), for: target)
        return true
    }

    /// The frame the inspector is editing: the picking tool's target, else the selected group's, else the Libra frame.
    func activeFrameTarget(in document: LibraDocument) -> FrameTarget? {
        if let target = tool.target { return target }
        if let group = selectedGroup(in: document) { return .group(group.id) }
        if selection.isEmpty { return .libra }
        return nil
    }

    // MARK: Groups

    /// Makes a group from the parts `items` stand for (the selection by default) and selects it.
    func createGroup(from items: Set<SidebarItem>? = nil, in document: inout LibraDocument) {
        if let id = document.createGroup(partIDs: partIDs(of: items ?? selection, in: document)) {
            selection = [.group(id)]
        }
    }

    /// Double-click in the sidebar: one group starts renaming in place.
    func primaryAction(on items: Set<SidebarItem>) {
        if items.count == 1, case .group(let id) = items.first {
            renamingGroupID = id
        }
    }

    /// Ends renaming a group, keeping `name` unless it's blank.
    func finishRenaming(_ id: UUID, to name: String, in document: inout LibraDocument) {
        if renamingGroupID == id {
            renamingGroupID = nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = document.groups.firstIndex(where: { $0.id == id }),
              document.groups[index].name != trimmed else { return }
        document.groups[index].name = trimmed
    }

    func selectParts(ofGroup id: UUID, in document: LibraDocument) {
        selection = Set((document.group(id)?.partIDs ?? []).map(SidebarItem.part))
    }

    func deleteGroup(_ id: UUID, in document: inout LibraDocument) {
        document.deleteGroup(id)
        selection.remove(.group(id))
    }

    // MARK: Context menus

    /// The right-click menu for parts, the same in the sidebar and the viewer.
    func partMenu(in document: LibraDocument) -> [PartMenuItem] {
        var items = [
            PartMenuItem(title: "Select Others", command: .selectOthers),
            PartMenuItem(title: "New Group", command: .newGroup)
        ]
        if !document.groups.isEmpty {
            let groups = document.groups.map { PartMenuItem(title: $0.name, command: .addToGroup($0.id)) }
            items.append(PartMenuItem(title: "Add to Group", children: groups))
        }
        return items
    }

    func perform(_ command: PartCommand, on partIDs: Set<UUID>, in document: inout LibraDocument) {
        switch command {
        case .selectOthers:
            selectOthers(like: partIDs, in: document)
        case .newGroup:
            createGroup(from: Set(partIDs.map(SidebarItem.part)), in: &document)
        case .addToGroup(let id):
            document.addParts(partIDs, toGroup: id)
        }
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
        let groupIndexByPart = Dictionary(
            document.groups.enumerated().flatMap { index, group in group.partIDs.map { ($0, index) } },
            uniquingKeysWith: { first, _ in first }
        )
        let parts = document.parts.map { part in
            var color: SIMD4<Float> = switch colorMode {
            case .cad:
                part.color.map { SIMD4($0.red, $0.green, $0.blue, 1) } ?? ViewerStyle.defaultPartColor
            case .massStatus:
                part.massProperties == nil ? ViewerStyle.unassignedColor : ViewerStyle.assignedColor
            case .group:
                groupIndexByPart[part.id].map { ViewerStyle.groupColors[$0 % ViewerStyle.groupColors.count] } ?? ViewerStyle.ungroupedColor
            }
            if selectedIDs.contains(part.id) {
                color = simd_mix(color, highlightColor, SIMD4(repeating: ViewerStyle.selectionTint))
            }
            return ViewerPart(id: part.id, geometry: part.geometry, color: color)
        }

        var markers: [Marker] = []
        var tooltips: [ViewerTooltip] = []
        let target = activeFrameTarget(in: document)
        var frameTargets = document.shownFrameTargets
        if let target, !frameTargets.contains(target) {
            frameTargets.append(target)
        }
        for frameTarget in frameTargets {
            if let frame = document.frame(for: frameTarget) {
                markers.append(.triad(frame, size: frameTarget == .libra ? .large : .small, selected: frameTarget == target))
                tooltips.append(ViewerTooltip(
                    point: frame.origin, radius: MarkerMesh.Style.originTooltipRadius, text: Self.frameName(frameTarget, in: document)
                ))
            }
        }
        let summary = MassSummary(parts: selectedIDs.isEmpty ? document.parts : document.parts(selectedIDs))
        if summary.properties.mass > 0 {
            markers.append(.centerOfMass(summary.properties.centerOfMass))
            tooltips.append(ViewerTooltip(
                point: summary.properties.centerOfMass, radius: MarkerMesh.Style.centerOfMassTooltipRadius,
                text: "Center of mass of \(centerOfMassOwner(in: document))"
            ))
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
            markers: markers,
            tooltips: tooltips
        )
    }

    /// What the center of mass marker belongs to: the selected part, assembly or group, a count of
    /// selected parts, or the whole assembly when nothing is selected.
    func centerOfMassOwner(in document: LibraDocument) -> String {
        if selection.count == 1 {
            switch selection.first {
            case .assembly(let path): if let name = path.last { return name }
            case .group(let id): if let group = document.group(id) { return group.name }
            default: break
            }
        }
        let partIDs = selectedPartIDs(in: document)
        if partIDs.count == 1, let id = partIDs.first, let part = document.part(id) {
            return part.name
        }
        return partIDs.isEmpty ? "the assembly" : "\(partIDs.count) selected parts"
    }

    /// What a frame's origin is called in the viewer, e.g. "Libra frame" or "Arm frame".
    static func frameName(_ target: FrameTarget, in document: LibraDocument) -> String {
        switch target {
        case .libra: "Libra frame"
        case .group(let id): "\(document.group(id)?.name ?? "Group") frame"
        }
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
