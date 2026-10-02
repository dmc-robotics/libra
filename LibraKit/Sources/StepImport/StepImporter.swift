import Foundation
import LibraKit
import StepBridge

public struct StepImportError: LocalizedError {
    public let message: String

    public var errorDescription: String? { message }
}

/// Reads STEP files through OpenCASCADE. An actor because OCCT's reader settings are global,
/// so imports must not overlap.
public actor StepImporter {
    public static let shared = StepImporter()

    public func importParts(from url: URL) throws -> [Part] {
        guard let result = libra_step_import(url.path(percentEncoded: false)) else {
            throw StepImportError(message: "The importer returned nothing.")
        }
        defer { libra_step_free(result) }
        if let errorMessage = result.pointee.errorMessage {
            throw StepImportError(message: String(cString: errorMessage))
        }
        let parts = UnsafeBufferPointer(start: result.pointee.parts, count: Int(result.pointee.partCount))
        return parts.map(Self.part)
    }

    private static func part(_ source: LibraStepPart) -> Part {
        let path = String(cString: source.path)
        return Part(
            name: String(cString: source.name),
            definitionName: String(cString: source.definitionName),
            path: path.isEmpty ? [] : path.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init),
            color: source.hasColor != 0
                ? RGBColor(red: source.color.0, green: source.color.1, blue: source.color.2)
                : nil,
            volumeProperties: VolumeProperties(
                volume: source.volume,
                centroid: vector(source.centroid),
                unitDensityInertia: inertia(source.inertia)
            ),
            geometry: geometry(source)
        )
    }

    private static func geometry(_ source: LibraStepPart) -> PartGeometry {
        let faces = buffer(source.faces, source.faceCount).map { face in
            FaceFeature(
                kind: FaceFeature.Kind(rawValue: Int(face.kind)) ?? .other,
                center: vector(face.center),
                direction: vector(face.direction),
                radius: face.radius,
                triangleRange: Int(face.triangleStart)..<Int(face.triangleStart + face.triangleCount),
                edgeRange: Int(face.edgeStart)..<Int(face.edgeStart + face.edgeCount)
            )
        }
        let edges = buffer(source.edges, source.edgeCount).map { edge in
            EdgeFeature(
                kind: EdgeFeature.Kind(rawValue: Int(edge.kind)) ?? .other,
                center: vector(edge.center),
                direction: vector(edge.direction),
                radius: edge.radius,
                pointRange: Int(edge.pointStart)..<Int(edge.pointStart + edge.pointCount)
            )
        }
        return PartGeometry(
            positions: points(source.positions, source.vertexCount),
            normals: points(source.normals, source.vertexCount),
            indices: Array(buffer(source.indices, source.triangleCount * 3)),
            faces: faces,
            faceEdges: Array(buffer(source.faceEdges, source.faceEdgeCount)),
            edges: edges,
            edgePoints: points(source.edgePoints, source.edgePointCount),
            vertices: points(source.vertices, source.vertexPointCount)
        )
    }

    private static func buffer<Element>(_ pointer: UnsafePointer<Element>?, _ count: Int32) -> UnsafeBufferPointer<Element> {
        UnsafeBufferPointer(start: count > 0 ? pointer : nil, count: Int(count))
    }

    private static func points(_ pointer: UnsafePointer<Float>?, _ count: Int32) -> [SIMD3<Float>] {
        let floats = buffer(pointer, count * 3)
        return (0..<Int(count)).map { SIMD3(floats[$0 * 3], floats[$0 * 3 + 1], floats[$0 * 3 + 2]) }
    }

    private static func vector(_ value: LibraStepVector) -> SIMD3<Double> {
        SIMD3(value.x, value.y, value.z)
    }

    private static func inertia(_ values: (Double, Double, Double, Double, Double, Double, Double, Double, Double)) -> InertiaTensor {
        // Row-major; OCCT's matrix of inertia already holds tensor entries (negative products of inertia)
        InertiaTensor(xx: values.0, yy: values.4, zz: values.8, xy: values.1, xz: values.2, yz: values.5)
    }
}
