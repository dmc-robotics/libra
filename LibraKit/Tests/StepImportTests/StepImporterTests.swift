import Foundation
import LibraKit
import StepImport
import Testing
import simd

/// Checks the import of Fixtures/assembly.step (see Tools/generate_fixtures.cpp) against closed-form values.
@Suite struct StepImporterTests {
    static let boxSize = SIMD3<Double>(0.010, 0.020, 0.030)
    static let cylinderRadius = 0.005
    static let cylinderHeight = 0.040

    let parts: [Part]

    init() async throws {
        let url = try #require(Bundle.module.url(forResource: "assembly", withExtension: "step", subdirectory: "Fixtures"))
        parts = try await StepImporter.shared.importParts(from: url)
    }

    func part(_ name: String) throws -> Part {
        try #require(parts.first { $0.name == name })
    }

    static var boxInertia: InertiaTensor {
        let volume = boxSize.x * boxSize.y * boxSize.z
        let squared = boxSize * boxSize
        return InertiaTensor(
            xx: volume * (squared.y + squared.z) / 12,
            yy: volume * (squared.x + squared.z) / 12,
            zz: volume * (squared.x + squared.y) / 12,
            xy: 0, xz: 0, yz: 0
        )
    }

    @Test func readsInstancesNamesAndPaths() throws {
        #expect(parts.map(\.name).sorted() == ["Box:1", "Box:2", "Cylinder:1"])
        #expect(try part("Box:1").definitionName == "Box")
        #expect(try part("Box:1").path == ["Fixture"])
        #expect(try part("Cylinder:1").path == ["Fixture", "Sub:1"])
    }

    @Test func readsColor() throws {
        let color = try #require(try part("Box:1").color)
        #expect(abs(color.red - 1) < 0.01 && color.green < 0.01 && color.blue < 0.01)
    }

    @Test func boxVolumeProperties() throws {
        let properties = try part("Box:1").volumeProperties
        expectClose(properties.volume, Self.boxSize.x * Self.boxSize.y * Self.boxSize.z)
        expectClose(properties.centroid, Self.boxSize / 2)
        expectClose(properties.unitDensityInertia, Self.boxInertia)
    }

    @Test func rotatedInstanceUsesTensorConvention() throws {
        let properties = try part("Box:2").volumeProperties
        let rotation = simd_double3x3(simd_quatd(angle: .pi / 4, axis: [0, 0, 1]))
        expectClose(properties.centroid, rotation * (Self.boxSize / 2) + [0.1, 0.05, 0])
        // R I Rᵀ with I in tensor form; a wrong sign convention would flip xy
        expectClose(properties.unitDensityInertia, Self.boxInertia.expressed(inAxes: rotation.transpose))
        #expect(properties.unitDensityInertia.xy != 0)
    }

    @Test func cylinderInNestedAssembly() throws {
        let properties = try part("Cylinder:1").volumeProperties
        let radius = Self.cylinderRadius
        let height = Self.cylinderHeight
        let volume = Double.pi * radius * radius * height
        expectClose(properties.volume, volume)
        expectClose(properties.centroid, [0, 0, 0.05 + height / 2])
        expectClose(properties.unitDensityInertia, InertiaTensor(
            xx: volume * (3 * radius * radius + height * height) / 12,
            yy: volume * (3 * radius * radius + height * height) / 12,
            zz: volume * radius * radius / 2,
            xy: 0, xz: 0, yz: 0
        ))
    }

    @Test func meshAndFeatures() throws {
        let box = try part("Box:1").geometry
        #expect(box.faces.count == 6)
        #expect(box.faces.allSatisfy { $0.kind == .plane && $0.triangleRange.count >= 2 })
        #expect(box.edges.count == 12)
        #expect(box.vertices.count == 8)
        #expect(box.triangleCount == box.faces.reduce(0) { $0 + $1.triangleRange.count })
        // Normals point out of the box: the +Z face's normal is +Z
        let top = try #require(box.faces.first { abs($0.center.z - 0.03) < 1e-9 })
        expectClose(top.direction, [0, 0, 1])

        let cylinder = try part("Cylinder:1").geometry
        let side = try #require(cylinder.faces.first { $0.kind == .cylinder })
        expectClose(side.center, [0, 0, 0.07])
        expectClose(abs(side.direction.z), 1)
        expectClose(side.radius, Self.cylinderRadius)
        let circles = cylinder.edges.filter { $0.kind == .circle }
        #expect(circles.count == 2)
        #expect(circles.contains { simd_distance($0.center, [0, 0, 0.09]) < 1e-9 })
        // The seam isn't drawn
        #expect(cylinder.edges.filter { $0.kind == .line }.allSatisfy { $0.pointRange.isEmpty })
    }

    @Test func missingFileThrows() async {
        await #expect(throws: StepImportError.self) {
            try await StepImporter.shared.importParts(from: URL(filePath: "/nonexistent/file.step"))
        }
    }
}

func expectClose(_ actual: Double, _ expected: Double, relative: Double = 1e-6, sourceLocation: SourceLocation = #_sourceLocation) {
    let tolerance = max(abs(expected) * relative, 1e-15)
    #expect(abs(actual - expected) <= tolerance, "\(actual) ≠ \(expected)", sourceLocation: sourceLocation)
}

func expectClose(_ actual: SIMD3<Double>, _ expected: SIMD3<Double>, tolerance: Double = 1e-9, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(simd_distance(actual, expected) <= tolerance, "\(actual) ≠ \(expected)", sourceLocation: sourceLocation)
}

func expectClose(_ actual: InertiaTensor, _ expected: InertiaTensor, relative: Double = 1e-6, sourceLocation: SourceLocation = #_sourceLocation) {
    let scale = max(abs(expected.xx), abs(expected.yy), abs(expected.zz))
    let difference = actual.matrix - expected.matrix
    let largest = [difference.columns.0, difference.columns.1, difference.columns.2].map { simd_reduce_max(simd_abs($0)) }.max() ?? 0
    #expect(largest <= scale * relative, "\(actual) ≠ \(expected)", sourceLocation: sourceLocation)
}

/// Fixtures/duplicate_names.step has two sibling subassemblies both named "Group".
@Suite struct DuplicateNameTests {
    @Test func siblingNamesAreMadeUnique() async throws {
        let url = try #require(Bundle.module.url(forResource: "duplicate_names", withExtension: "step", subdirectory: "Fixtures"))
        let parts = try await StepImporter.shared.importParts(from: url)
        let occurrences = parts.map { $0.path + [$0.name] }
        #expect(Set(occurrences).count == parts.count)
        #expect(Set(parts.map(\.path)).isSuperset(of: [["Duplicates", "Group"], ["Duplicates", "Group (2)"]]))
    }
}

/// Snapping on the fixture's cylinder: radius 5 mm, axis along Z from z = 50 to 90 mm.
@Suite struct CylinderSnapTests {
    let cylinder: Part
    let camera: OrthographicCamera

    init() async throws {
        let url = try #require(Bundle.module.url(forResource: "assembly", withExtension: "step", subdirectory: "Fixtures"))
        let parts = try await StepImporter.shared.importParts(from: url)
        cylinder = try #require(parts.first { $0.name == "Cylinder:1" })
        var camera = OrthographicCamera(viewportSize: [800, 600], sceneBounds: cylinder.geometry.bounds)
        camera.look(from: .front, in: .file)
        camera.fit(cylinder.geometry.bounds)
        self.camera = camera
    }

    /// The origin snap with the cursor over the cylinder's front surface at height `z`.
    func originSnap(atHeight z: Double) throws -> Snap {
        let cursor = camera.project([0, -0.005, z])
        let hit = try #require(PartPicker(parts: [cylinder]).pick(camera.ray(through: cursor)))
        return try #require(Snapper(camera: camera, cursor: cursor).originSnap(for: hit, in: cylinder.geometry))
    }

    @Test func middleSnapsToCenter() throws {
        let snap = try originSnap(atHeight: 0.0702)
        #expect(snap.kind == .axisCenter)
        expectClose(snap.point, [0, 0, 0.07])
    }

    @Test func elsewhereSnapsToAxis() throws {
        let snap = try originSnap(atHeight: 0.08)
        #expect(snap.kind == .axisPoint)
        expectClose(snap.point, [0, 0, 0.08], tolerance: 1e-6)
    }

    @Test func nearTheEndSnapsToCircleCenter() throws {
        let snap = try originSnap(atHeight: 0.0899)
        #expect(snap.kind == .circleCenter)
        expectClose(snap.point, [0, 0, 0.09])
    }
}
