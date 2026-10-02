import LibraKit
import Metal

/// GPU copies of one part's geometry. Geometry never changes after import, so these are built once per part.
struct PartBuffers {
    let positions: MTLBuffer
    let normals: MTLBuffer
    let indices: MTLBuffer
    let indexCount: Int
    /// Edge polylines as a line list (two vertices per segment).
    let edgeVertices: MTLBuffer?
    let edgeVertexCount: Int

    init?(device: MTLDevice, geometry: PartGeometry) {
        guard !geometry.indices.isEmpty,
              let positions = Self.buffer(device, geometry.positions),
              let normals = Self.buffer(device, geometry.normals),
              let indices = Self.buffer(device, geometry.indices) else { return nil }
        self.positions = positions
        self.normals = normals
        self.indices = indices
        indexCount = geometry.indices.count

        var segments: [SIMD3<Float>] = []
        for edge in geometry.edges.indices {
            let points = geometry.points(ofEdge: edge)
            for (start, end) in zip(points, points.dropFirst()) {
                segments += [start, end]
            }
        }
        edgeVertices = Self.buffer(device, segments)
        edgeVertexCount = segments.count
    }

    static func buffer<Element>(_ device: MTLDevice, _ values: [Element]) -> MTLBuffer? {
        guard !values.isEmpty else { return nil }
        return values.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
    }
}
