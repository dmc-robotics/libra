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

    @Test func bodiesTakePartsExclusively() throws {
        var document = Self.makeDocument()
        let model = DocumentModel()
        model.selection = [.assembly(["Robot"])]
        model.createBody(in: &document)
        let first = try #require(document.bodies.first)
        #expect(first.partIDs.count == 2)
        #expect(model.selection == [.body(first.id)])

        model.selection = [.part(document.parts[1].id)]
        model.createBody(in: &document)
        #expect(document.bodies[0].partIDs == [document.parts[0].id])
        #expect(document.bodies[1].partIDs == [document.parts[1].id])
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

    @Test func overrideFrameIsEditable() {
        var document = Self.makeDocument()
        let model = DocumentModel()
        let id = document.parts[0].id
        document.parts[0].mass = .override(MassOverride(mass: 1, centerOfMass: .zero, inertia: .zero, frame: .file))
        model.setFrame(Frame.file.moved(to: [1, 2, 3]), for: .override(id), in: &document)
        #expect(model.frame(for: .override(id), in: &document)?.origin == [1, 2, 3])
    }

    @Test func sceneMarksSelectionAndCenterOfMass() {
        var document = Self.makeDocument()
        document.parts[0].mass = .measured(1)
        let model = DocumentModel()
        model.selection = [.part(document.parts[0].id)]
        let highlight: SIMD4<Float> = [1, 0, 0, 1]
        let scene = model.scene(for: document, highlightColor: highlight)
        #expect(scene.parts[0].color != scene.parts[1].color)
        #expect(scene.markers.contains(.centerOfMass([0.05, 0.05, 0.05])))
        #expect(scene.markers.contains(.triad(.file, emphasized: false)))
    }
}

extension DocumentModel {
    /// Lets tests read frames with the same call shape they write them.
    func frame(for target: FrameTarget, in document: inout LibraDocument) -> Frame? {
        frame(for: target, in: document)
    }
}
