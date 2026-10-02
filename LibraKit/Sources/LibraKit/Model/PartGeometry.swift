import Foundation
import simd

/// A part's render mesh and the B-rep features used for snapping, in file coordinates (meters).
/// Triangles of each face are contiguous; edges are polylines.
public struct PartGeometry: Hashable, Sendable {
    public var positions: [SIMD3<Float>]
    public var normals: [SIMD3<Float>]
    public var indices: [UInt32]
    public var faces: [FaceFeature]
    /// `faces[i].edgeRange` indexes into this; values are indices into `edges`.
    public var faceEdges: [Int32]
    public var edges: [EdgeFeature]
    public var edgePoints: [SIMD3<Float>]
    /// Topological vertices (corners), for snapping.
    public var vertices: [SIMD3<Float>]

    public init(
        positions: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32], faces: [FaceFeature],
        faceEdges: [Int32], edges: [EdgeFeature], edgePoints: [SIMD3<Float>], vertices: [SIMD3<Float>]
    ) {
        self.positions = positions
        self.normals = normals
        self.indices = indices
        self.faces = faces
        self.faceEdges = faceEdges
        self.edges = edges
        self.edgePoints = edgePoints
        self.vertices = vertices
    }

    public var triangleCount: Int { indices.count / 3 }

    public func edgeIndices(ofFace face: Int) -> ArraySlice<Int32> {
        faceEdges[faces[face].edgeRange]
    }

    public func points(ofEdge edge: Int) -> ArraySlice<SIMD3<Float>> {
        edgePoints[edges[edge].pointRange]
    }

    /// The face a triangle belongs to.
    public func face(ofTriangle triangle: Int) -> Int? {
        // Faces are stored in triangle order, so binary search their starts
        var low = 0
        var high = faces.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let range = faces[middle].triangleRange
            if triangle < range.lowerBound {
                high = middle - 1
            } else if triangle >= range.upperBound {
                low = middle + 1
            } else {
                return middle
            }
        }
        return nil
    }

    public var bounds: BoundingBox {
        BoundingBox(points: positions.map { SIMD3<Double>($0) })
    }
}

public struct FaceFeature: Codable, Hashable, Sendable {
    public enum Kind: Int, Codable, Sendable {
        case other, plane, cylinder, cone, sphere, torus
    }

    public var kind: Kind
    /// Plane: area centroid. Cylinder, cone, torus: point on the axis level with the middle of the face. Sphere: center.
    public var center: SIMD3<Double>
    /// Plane: outward normal. Cylinder, cone, torus: axis direction. Otherwise zero.
    public var direction: SIMD3<Double>
    public var radius: Double
    public var triangleRange: Range<Int>
    public var edgeRange: Range<Int>

    public init(kind: Kind, center: SIMD3<Double>, direction: SIMD3<Double>, radius: Double, triangleRange: Range<Int>, edgeRange: Range<Int>) {
        self.kind = kind
        self.center = center
        self.direction = direction
        self.radius = radius
        self.triangleRange = triangleRange
        self.edgeRange = edgeRange
    }
}

public struct EdgeFeature: Codable, Hashable, Sendable {
    public enum Kind: Int, Codable, Sendable {
        case other, line, circle
    }

    public var kind: Kind
    /// Circle center; zero otherwise.
    public var center: SIMD3<Double>
    /// Line: direction. Circle: axis normal.
    public var direction: SIMD3<Double>
    public var radius: Double
    /// Empty for seam and degenerate edges, which aren't drawn.
    public var pointRange: Range<Int>

    public init(kind: Kind, center: SIMD3<Double>, direction: SIMD3<Double>, radius: Double, pointRange: Range<Int>) {
        self.kind = kind
        self.center = center
        self.direction = direction
        self.radius = radius
        self.pointRange = pointRange
    }
}

public struct BoundingBox: Hashable, Sendable {
    public var minimum: SIMD3<Double>
    public var maximum: SIMD3<Double>

    public static let empty = BoundingBox(minimum: SIMD3(repeating: .infinity), maximum: SIMD3(repeating: -.infinity))

    public init(minimum: SIMD3<Double>, maximum: SIMD3<Double>) {
        self.minimum = minimum
        self.maximum = maximum
    }

    public init(points: [SIMD3<Double>]) {
        self = .empty
        for point in points {
            include(point)
        }
    }

    public var isEmpty: Bool { minimum.x > maximum.x }
    public var center: SIMD3<Double> { (minimum + maximum) / 2 }
    public var diagonal: Double { isEmpty ? 0 : simd_distance(minimum, maximum) }

    public mutating func include(_ point: SIMD3<Double>) {
        minimum = simd_min(minimum, point)
        maximum = simd_max(maximum, point)
    }

    public func union(_ other: BoundingBox) -> BoundingBox {
        BoundingBox(minimum: simd_min(minimum, other.minimum), maximum: simd_max(maximum, other.maximum))
    }

    public var corners: [SIMD3<Double>] {
        (0..<8).map { index in
            SIMD3(
                index & 1 == 0 ? minimum.x : maximum.x,
                index & 2 == 0 ? minimum.y : maximum.y,
                index & 4 == 0 ? minimum.z : maximum.z
            )
        }
    }
}

// Meshes are stored as base64 binary blobs, which keeps .libra files compact and fast to load
extension PartGeometry: Codable {
    private enum CodingKeys: String, CodingKey {
        case positions, normals, indices, faces, faceEdges, edges, edgePoints, vertices
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        positions = try BinaryCoding.vectors(container.decode(Data.self, forKey: .positions))
        normals = try BinaryCoding.vectors(container.decode(Data.self, forKey: .normals))
        indices = try BinaryCoding.values(container.decode(Data.self, forKey: .indices))
        faces = try container.decode([FaceFeature].self, forKey: .faces)
        faceEdges = try BinaryCoding.values(container.decode(Data.self, forKey: .faceEdges))
        edges = try container.decode([EdgeFeature].self, forKey: .edges)
        edgePoints = try BinaryCoding.vectors(container.decode(Data.self, forKey: .edgePoints))
        vertices = try BinaryCoding.vectors(container.decode(Data.self, forKey: .vertices))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(BinaryCoding.data(vectors: positions), forKey: .positions)
        try container.encode(BinaryCoding.data(vectors: normals), forKey: .normals)
        try container.encode(BinaryCoding.data(values: indices), forKey: .indices)
        try container.encode(faces, forKey: .faces)
        try container.encode(BinaryCoding.data(values: faceEdges), forKey: .faceEdges)
        try container.encode(edges, forKey: .edges)
        try container.encode(BinaryCoding.data(vectors: edgePoints), forKey: .edgePoints)
        try container.encode(BinaryCoding.data(vectors: vertices), forKey: .vertices)
    }
}

/// Little-endian packing of numeric arrays (the only byte order Libra runs on).
enum BinaryCoding {
    struct CorruptData: Error {}

    static func data<Value: BitwiseCopyable>(values: [Value]) -> Data {
        values.withUnsafeBytes { Data($0) }
    }

    static func values<Value: BitwiseCopyable>(_ data: Data) throws -> [Value] {
        let stride = MemoryLayout<Value>.stride
        guard data.count % stride == 0 else { throw CorruptData() }
        return [Value](unsafeUninitializedCapacity: data.count / stride) { buffer, count in
            _ = data.copyBytes(to: buffer)
            count = data.count / stride
        }
    }

    // SIMD3<Float> has 16-byte stride, so store packed xyz floats
    static func data(vectors: [SIMD3<Float>]) -> Data {
        data(values: vectors.flatMap { [$0.x, $0.y, $0.z] })
    }

    static func vectors(_ data: Data) throws -> [SIMD3<Float>] {
        let floats: [Float] = try values(data)
        guard floats.count % 3 == 0 else { throw CorruptData() }
        return stride(from: 0, to: floats.count, by: 3).map { SIMD3(floats[$0], floats[$0 + 1], floats[$0 + 2]) }
    }
}
