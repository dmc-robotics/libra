import Foundation
@testable import Libra
import LibraKit
import Testing
import simd

@MainActor
@Suite struct DocumentModelTests {
    /// Two parts in "Robot", one of them in subassembly "Robot/Arm", as 0.1 m cubes.
    static func makeDocument() -> LibraDocument {
        LibraDocument(parts: [
            cube(name: "Base", path: ["Robot"], corner: .zero),
            cube(name: "Link", path: ["Robot", "Arm"], corner: [0.2, 0, 0])
        ])
    }

    static func cube(name: String, path: [String], corner: SIMD3<Double>) -> Part {
        let size = 0.1
        let volume = size * size * size
        let inertia = volume * 2 * size * size / 12
        return Part(
            name: name, definitionName: name, path: path, color: nil,
            volumeProperties: VolumeProperties(
                volume: volume, centroid: corner + SIMD3(repeating: size / 2),
                unitDensityInertia: InertiaTensor(xx: inertia, yy: inertia, zz: inertia, xy: 0, xz: 0, yz: 0)
            ),
            geometry: PartGeometry(positions: [], normals: [], indices: [], faces: [], faceEdges: [], edges: [], edgePoints: [], vertices: [])
        )
    }

    static func pointer(hitting partID: UUID?, at point: SIMD3<Double> = .zero) -> ViewerPointer {
        ViewerPointer(
            hit: partID.map { PickHit(partID: $0, triangle: 0, face: nil, point: point, distance: 1) },
            camera: OrthographicCamera(),
            cursor: .zero
        )
    }

    @Test func outlineFollowsAssemblyPaths() {
        let outline = DocumentModel.outline(for: Self.makeDocument().parts)
        #expect(outline.map(\.name) == ["Robot"])
        let robot = outline[0].children ?? []
        #expect(robot.map(\.name) == ["Arm", "Base"])
        #expect(robot[0].id == .assembly(["Robot", "Arm"]))
        #expect(robot[0].children?.map(\.name) == ["Link"])
    }

    @Test func selectingAnAssemblySelectsItsParts() {
        let document = Self.makeDocument()
        let model = DocumentModel()
        model.selection = [.assembly(["Robot", "Arm"])]
        #expect(model.selectedPartIDs(in: document) == [document.parts[1].id])
        model.selection = [.assembly(["Robot"])]
        #expect(model.selectedPartIDs(in: document).count == 2)
    }

    @Test func clickingSelectsAndExtends() {
        var document = Self.makeDocument()
        let model = DocumentModel()
        let base = document.parts[0].id
        let link = document.parts[1].id
        model.click(Self.pointer(hitting: base), extendingSelection: false, in: &document)
        #expect(model.selection == [.part(base)])
        model.click(Self.pointer(hitting: link), extendingSelection: true, in: &document)
        #expect(model.selection == [.part(base), .part(link)])
        model.click(Self.pointer(hitting: nil), extendingSelection: false, in: &document)
        #expect(model.selection.isEmpty)
    }

    @Test func rightClickTargetsTheSelectionOrThePartUnderIt() {
        var document = Self.makeDocument()
        let model = DocumentModel()
        let base = document.parts[0].id
        let link = document.parts[1].id
        model.click(Self.pointer(hitting: base), extendingSelection: false, in: &document)
        model.click(Self.pointer(hitting: link), extendingSelection: true, in: &document)
        #expect(model.contextMenuPartIDs(for: Self.pointer(hitting: link), in: document) == [base, link])
        #expect(model.selection == [.part(base), .part(link)])

        model.selection = [.part(base)]
        #expect(model.contextMenuPartIDs(for: Self.pointer(hitting: link), in: document) == [link])
        #expect(model.selection == [.part(link)])

        #expect(model.contextMenuPartIDs(for: Self.pointer(hitting: nil), in: document) == nil)
        model.tool = .pickOrigin(.libra)
        #expect(model.contextMenuPartIDs(for: Self.pointer(hitting: link), in: document) == nil)
    }

    @Test func partMenuMakesAGroup() throws {
        var document = Self.makeDocument()
        let model = DocumentModel()
        #expect(model.partMenu(in: document).map(\.title) == ["Select Others", "New Group"])
        model.perform(.newGroup, on: [document.parts[1].id], in: &document)
        let group = try #require(document.groups.first)
        #expect(group.partIDs == [document.parts[1].id])
        #expect(model.selection == [.group(group.id)])
    }

    @Test func partMenuAddsToAGroup() throws {
        var document = Self.makeDocument()
        let model = DocumentModel()
        let createdGroup = document.createGroup(named: "Arm", partIDs: [document.parts[1].id])
        let group = try #require(createdGroup)
        let addToGroup = try #require(model.partMenu(in: document).last)
        #expect(addToGroup.title == "Add to Group")
        #expect(addToGroup.command == nil)
        #expect(addToGroup.children.map(\.title) == ["Arm"])
        #expect(addToGroup.children.map(\.command) == [.addToGroup(group)])

        model.perform(.addToGroup(group), on: [document.parts[0].id], in: &document)
        #expect(document.group(group)?.partIDs == document.parts.map(\.id))
    }

    @Test func selectOthersSelectsEveryInstance() {
        var document = Self.makeDocument()
        document.parts.append(Self.cube(name: "Base", path: ["Robot"], corner: [0.4, 0, 0]))
        let model = DocumentModel()
        model.selectOthers(like: [document.parts[0].id], in: document)
        #expect(model.selection == [.part(document.parts[0].id), .part(document.parts[2].id)])
    }

    @Test func createGroupFromSidebarItemsSelectsIt() throws {
        var document = Self.makeDocument()
        let model = DocumentModel()
        model.createGroup(from: [.assembly(["Robot", "Arm"])], in: &document)
        let group = try #require(document.groups.first)
        #expect(group.partIDs == [document.parts[1].id])
        #expect(model.selection == [.group(group.id)])
    }

    @Test func keysTurnTheActiveFrame() {
        var document = Self.makeDocument()
        let model = DocumentModel()
        // Nothing selected: the Libra frame is active
        #expect(model.handleKey("z", shift: false, in: &document))
        #expect(document.libraFrame.xAxis == [0, 1, 0])
        #expect(model.handleKey("Z", shift: true, in: &document))
        #expect(document.libraFrame == .file)
        #expect(!model.handleKey("q", shift: false, in: &document))
    }

    @Test func escapeCancelsPicking() {
        var document = Self.makeDocument()
        let model = DocumentModel()
        model.tool = .pickOrigin(.libra)
        #expect(model.handleKey("\u{1b}", shift: false, in: &document))
        #expect(model.tool == .select)
    }

    @Test func sceneMarksSelectionAndCenterOfMass() {
        var document = Self.makeDocument()
        document.parts[0].mass = 1
        let model = DocumentModel()
        model.selection = [.part(document.parts[0].id)]
        let highlight: SIMD4<Float> = [1, 0, 0, 1]
        let scene = model.scene(for: document, highlightColor: highlight)
        #expect(scene.parts[0].color != scene.parts[1].color)
        #expect(scene.markers.contains(.centerOfMass([0.05, 0.05, 0.05])))
        #expect(scene.markers.contains(.triad(.file, size: .large, selected: false)))
    }

    @Test func sceneSelectsTheFrameBeingEdited() {
        var document = Self.makeDocument()
        let model = DocumentModel()
        let highlight: SIMD4<Float> = [1, 0, 0, 1]
        #expect(model.scene(for: document, highlightColor: highlight).markers.contains(.triad(.file, size: .large, selected: true)))

        model.createGroup(from: [.part(document.parts[0].id)], in: &document)
        let markers = model.scene(for: document, highlightColor: highlight).markers
        #expect(markers.contains(.triad(.file, size: .large, selected: false)))
        #expect(markers.contains(.triad(.file, size: .small, selected: true)))
    }

    @Test func frameOriginsNameTheirFrames() throws {
        var document = Self.makeDocument()
        let model = DocumentModel()
        let createdGroup = document.createGroup(named: "Arm", partIDs: [document.parts[1].id])
        let id = try #require(createdGroup)
        document.setFrame(Frame.file.moved(to: [1, 0, 0]), for: .group(id))
        document.setShowsFrame(true, for: .group(id))
        let tooltips = model.scene(for: document, highlightColor: [1, 0, 0, 1]).tooltips
        #expect(tooltips.map(\.text) == ["Libra frame", "Arm frame"])
        #expect(tooltips.map(\.point) == [.zero, [1, 0, 0]])
    }

    @Test func centerOfMassNamesWhatItBelongsTo() throws {
        var document = Self.makeDocument()
        document.setMass(1, forParts: Set(document.parts.map(\.id)))
        let createdGroup = document.createGroup(named: "Arm", partIDs: [document.parts[1].id])
        let group = try #require(createdGroup)
        let model = DocumentModel()
        func centerOfMassText() -> String? {
            model.scene(for: document, highlightColor: [1, 0, 0, 1]).tooltips.first { $0.text.hasPrefix("Center of mass") }?.text
        }
        #expect(centerOfMassText() == "Center of mass of the assembly")
        model.selection = [.part(document.parts[0].id)]
        #expect(centerOfMassText() == "Center of mass of Base")
        model.selection = [.assembly(["Robot", "Arm"])]
        #expect(centerOfMassText() == "Center of mass of Arm")
        model.selection = [.group(group)]
        #expect(centerOfMassText() == "Center of mass of Arm")
        model.selection = [.part(document.parts[0].id), .part(document.parts[1].id)]
        #expect(centerOfMassText() == "Center of mass of 2 selected parts")
        model.selection = [.part(document.parts[1].id), .assembly(["Robot", "Arm"])]
        #expect(centerOfMassText() == "Center of mass of Link")
    }

    @Test func sceneDrawsShownFramesWhenNotSelected() throws {
        var document = Self.makeDocument()
        let model = DocumentModel()
        let createdGroup = document.createGroup(partIDs: [document.parts[0].id])
        let id = try #require(createdGroup)
        let groupFrame = Frame.file.moved(to: [1, 0, 0])
        document.setFrame(groupFrame, for: .group(id))
        let highlight: SIMD4<Float> = [1, 0, 0, 1]
        #expect(!model.scene(for: document, highlightColor: highlight).markers.contains(.triad(groupFrame, size: .small, selected: false)))

        document.setShowsFrame(true, for: .group(id))
        #expect(model.scene(for: document, highlightColor: highlight).markers.contains(.triad(groupFrame, size: .small, selected: false)))

        // Selected, it's drawn once, glowing
        model.selection = [.group(id)]
        let markers = model.scene(for: document, highlightColor: highlight).markers
        #expect(markers.contains(.triad(groupFrame, size: .small, selected: true)))
        #expect(!markers.contains(.triad(groupFrame, size: .small, selected: false)))
    }
}
