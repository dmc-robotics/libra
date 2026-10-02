import Foundation
@testable import LibraKit
import Testing
import simd

func expectClose(_ actual: Double, _ expected: Double, tolerance: Double = 1e-9, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(abs(actual - expected) <= tolerance, "\(actual) ≠ \(expected)", sourceLocation: sourceLocation)
}

func expectClose(_ actual: SIMD3<Double>, _ expected: SIMD3<Double>, tolerance: Double = 1e-9, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(simd_distance(actual, expected) <= tolerance, "\(actual) ≠ \(expected)", sourceLocation: sourceLocation)
}

func expectClose(_ actual: SIMD2<Double>, _ expected: SIMD2<Double>, tolerance: Double = 1e-6, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(simd_distance(actual, expected) <= tolerance, "\(actual) ≠ \(expected)", sourceLocation: sourceLocation)
}

func expectClose(_ actual: InertiaTensor, _ expected: InertiaTensor, tolerance: Double = 1e-12, sourceLocation: SourceLocation = #_sourceLocation) {
    let difference = actual.matrix - expected.matrix
    let largest = [difference.columns.0, difference.columns.1, difference.columns.2].map { simd_reduce_max(simd_abs($0)) }.max() ?? 0
    #expect(largest <= tolerance, "\(actual) ≠ \(expected)", sourceLocation: sourceLocation)
}

enum Fixtures {
    /// Unit-density properties of an axis-aligned solid box with one corner at `corner`.
    static func boxProperties(size: SIMD3<Double>, corner: SIMD3<Double> = .zero) -> VolumeProperties {
        let volume = size.x * size.y * size.z
        let squared = size * size
        return VolumeProperties(
            volume: volume,
            centroid: corner + size / 2,
            unitDensityInertia: InertiaTensor(
                xx: volume * (squared.y + squared.z) / 12,
                yy: volume * (squared.x + squared.z) / 12,
                zz: volume * (squared.x + squared.y) / 12,
                xy: 0, xz: 0, yz: 0
            )
        )
    }

    /// An axis-aligned box mesh with six planar faces, edges and corners, like the importer produces.
    static func boxGeometry(size: SIMD3<Double>, corner: SIMD3<Double> = .zero) -> PartGeometry {
        let minimum = SIMD3<Float>(corner)
        let maximum = SIMD3<Float>(corner + size)
        func vertex(_ index: Int) -> SIMD3<Float> {
            SIMD3(index & 1 == 0 ? minimum.x : maximum.x, index & 2 == 0 ? minimum.y : maximum.y, index & 4 == 0 ? minimum.z : maximum.z)
        }
        // Each face: four corner indices (counterclockwise seen from outside) and its outward normal
        let faceCorners: [([Int], SIMD3<Double>)] = [
            ([0, 2, 6, 4], [-1, 0, 0]), ([1, 5, 7, 3], [1, 0, 0]),
            ([0, 4, 5, 1], [0, -1, 0]), ([2, 3, 7, 6], [0, 1, 0]),
            ([0, 1, 3, 2], [0, 0, -1]), ([4, 6, 7, 5], [0, 0, 1])
        ]
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var faces: [FaceFeature] = []
        var faceEdges: [Int32] = []
        var edges: [EdgeFeature] = []
        var edgePoints: [SIMD3<Float>] = []
        var edgeIndexByCorners: [Set<Int>: Int] = [:]
        for (cornerIndices, normal) in faceCorners {
            let base = UInt32(positions.count)
            for index in cornerIndices {
                positions.append(vertex(index))
                normals.append(SIMD3<Float>(normal))
            }
            let triangleStart = indices.count / 3
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
            let edgeStart = faceEdges.count
            for side in 0..<4 {
                let pair: Set = [cornerIndices[side], cornerIndices[(side + 1) % 4]]
                let edgeIndex = edgeIndexByCorners[pair] ?? {
                    let start = vertex(cornerIndices[side])
                    let end = vertex(cornerIndices[(side + 1) % 4])
                    edges.append(EdgeFeature(
                        kind: .line, center: .zero, direction: simd_normalize(SIMD3<Double>(end - start)), radius: 0,
                        pointRange: edgePoints.count..<(edgePoints.count + 2)
                    ))
                    edgePoints += [start, end]
                    edgeIndexByCorners[pair] = edges.count - 1
                    return edges.count - 1
                }()
                faceEdges.append(Int32(edgeIndex))
            }
            let points = cornerIndices.map { SIMD3<Double>(vertex($0)) }
            faces.append(FaceFeature(
                kind: .plane, center: points.reduce(.zero, +) / 4, direction: normal, radius: 0,
                triangleRange: triangleStart..<(triangleStart + 2), edgeRange: edgeStart..<faceEdges.count
            ))
        }
        return PartGeometry(
            positions: positions, normals: normals, indices: indices, faces: faces, faceEdges: faceEdges,
            edges: edges, edgePoints: edgePoints, vertices: (0..<8).map(vertex)
        )
    }

    static func boxPart(name: String = "Box", size: SIMD3<Double>, corner: SIMD3<Double> = .zero, mass: MassAssignment = .unassigned) -> Part {
        Part(
            name: name, definitionName: name, path: ["Assembly"], color: nil,
            volumeProperties: boxProperties(size: size, corner: corner),
            geometry: boxGeometry(size: size, corner: corner), mass: mass
        )
    }
}
