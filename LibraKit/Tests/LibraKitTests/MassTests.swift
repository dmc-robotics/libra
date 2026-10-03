@testable import LibraKit
import Testing
import simd

@Suite struct MassTests {
    @Test func measuredMassScalesUnitDensityInertia() throws {
        let size = SIMD3<Double>(0.1, 0.2, 0.3)
        let part = Fixtures.boxPart(size: size, mass: 2)
        let properties = try #require(part.massProperties)
        expectClose(properties.mass, 2)
        expectClose(properties.centerOfMass, size / 2)
        // Solid box: Ixx = m (b² + c²) / 12
        expectClose(properties.inertia, InertiaTensor(
            xx: 2 * (0.04 + 0.09) / 12, yy: 2 * (0.01 + 0.09) / 12, zz: 2 * (0.01 + 0.04) / 12, xy: 0, xz: 0, yz: 0
        ))
    }

    @Test func masslessAndVolumelessPartsHaveNoProperties() {
        #expect(Fixtures.boxPart(size: [1, 1, 1]).massProperties == nil)
        var flat = Fixtures.boxPart(size: [1, 1, 1], mass: 1)
        flat.volumeProperties.volume = 0
        #expect(flat.massProperties == nil)
    }

    @Test func combiningUsesParallelAxisTheorem() {
        // Two 1 kg point masses 2 m apart along X: COM in the middle, Iyy = Izz = 2 · 1 · 1²
        let left = MassProperties(mass: 1, centerOfMass: [-1, 5, 0], inertia: .zero)
        let right = MassProperties(mass: 1, centerOfMass: [1, 5, 0], inertia: .zero)
        let combined = MassProperties.combined([left, right])
        expectClose(combined.mass, 2)
        expectClose(combined.centerOfMass, [0, 5, 0])
        expectClose(combined.inertia, InertiaTensor(xx: 0, yy: 2, zz: 2, xy: 0, xz: 0, yz: 0))
    }

    @Test func combiningOffDiagonalMassGivesNegativeProduct() {
        // Point masses on the line y = x: the tensor's xy entry is -Σ m x y < 0
        let combined = MassProperties.combined([
            MassProperties(mass: 1, centerOfMass: [1, 1, 0], inertia: .zero),
            MassProperties(mass: 1, centerOfMass: [-1, -1, 0], inertia: .zero)
        ])
        expectClose(combined.inertia.xy, -2)
    }

    @Test func expressingInARotatedFrame() {
        let properties = MassProperties(
            mass: 3, centerOfMass: [1, 2, 3], inertia: InertiaTensor(xx: 1, yy: 2, zz: 3, xy: 0, xz: 0, yz: 0)
        )
        // Frame at (1, 0, 0) turned a quarter about Z: its X is file +Y, its Y is file -X
        let frame = Frame.file.moved(to: [1, 0, 0]).rotatedQuarterTurn(about: .z)
        let local = properties.expressed(in: frame)
        expectClose(local.centerOfMass, [2, 0, 3])
        expectClose(local.inertia, InertiaTensor(xx: 2, yy: 1, zz: 3, xy: 0, xz: 0, yz: 0))
    }

    @Test func inertiaAboutOrigin() {
        let properties = MassProperties(mass: 2, centerOfMass: [0, 0, 3], inertia: .zero)
        expectClose(properties.inertiaAboutOrigin, InertiaTensor(xx: 18, yy: 18, zz: 0, xy: 0, xz: 0, yz: 0))
    }

    @Test func inertiaAboutEitherReference() {
        // Off-axis, so the product of inertia picks up -m x y
        let inertia = InertiaTensor(xx: 1, yy: 2, zz: 3, xy: 0, xz: 0, yz: 0)
        let properties = MassProperties(mass: 2, centerOfMass: [1, 2, 0], inertia: inertia)
        #expect(properties.inertia(about: .centerOfMass) == inertia)
        expectClose(properties.inertia(about: .origin), InertiaTensor(xx: 1 + 8, yy: 2 + 2, zz: 3 + 10, xy: -4, xz: 0, yz: 0))
    }

    @Test func summaryCountsUnassigned() {
        let parts = [
            Fixtures.boxPart(size: [1, 1, 1], mass: 1),
            Fixtures.boxPart(size: [1, 1, 1], corner: [2, 0, 0], mass: 1),
            Fixtures.boxPart(size: [1, 1, 1])
        ]
        let summary = MassSummary(parts: parts)
        #expect(summary.partCount == 3)
        #expect(summary.unassignedCount == 1)
        expectClose(summary.properties.centerOfMass, [1.5, 0.5, 0.5])
    }
}

@Suite struct FrameTests {
    @Test func quarterTurnsStayExact() {
        var frame = Frame.file
        for _ in 0..<4 {
            frame = frame.rotatedQuarterTurn(about: .x)
        }
        #expect(frame == .file)
        let turned = Frame.file.rotatedQuarterTurn(about: .z)
        #expect(turned.xAxis == [0, 1, 0])
        #expect(turned.yAxis == [-1, 0, 0])
        #expect(turned.zAxis == [0, 0, 1])
    }

    @Test func aligningUsesSmallestRotation() {
        // Pointing Z along file Y should leave X alone
        let frame = Frame.file.aligning(.z, to: [0, 1, 0])
        expectClose(frame.zAxis, [0, 1, 0])
        expectClose(frame.xAxis, [1, 0, 0])
        expectClose(simd_cross(frame.xAxis, frame.yAxis), frame.zAxis)
    }

    @Test func aligningToOppositeDirection() {
        let frame = Frame.file.aligning(.z, to: [0, 0, -1])
        expectClose(frame.zAxis, [0, 0, -1])
        expectClose(simd_cross(frame.xAxis, frame.yAxis), frame.zAxis)
    }

    @Test func flippingKeepsRightHanded() {
        let frame = Frame.file.flipped(.z)
        #expect(frame.zAxis == [0, 0, -1])
        expectClose(simd_cross(frame.xAxis, frame.yAxis), frame.zAxis)
    }

    @Test func localAndFileConversionsAreInverse() {
        let frame = Frame.file.moved(to: [1, 2, 3]).rotatedQuarterTurn(about: .y).rotatedQuarterTurn(about: .z)
        let point = SIMD3<Double>(0.3, -0.7, 2)
        expectClose(frame.filePoint(frame.localPoint(point)), point)
    }

    @Test func poseRelativeToParent() {
        let parent = Frame.file.moved(to: [1, 0, 0]).rotatedQuarterTurn(about: .z)
        let child = Frame.file.moved(to: [1, 1, 0])
        let pose = child.pose(relativeTo: parent)
        expectClose(pose.position, [1, 0, 0])
        // The child's X (file +X) is the parent's -Y
        expectClose(pose.rotation.columns.0, [0, -1, 0])
    }
}
