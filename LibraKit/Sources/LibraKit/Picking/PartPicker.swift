import Foundation
import simd

public struct PickHit: Hashable, Sendable {
    public var partID: UUID
    public var triangle: Int
    public var face: Int?
    /// Where the ray hit, in file coordinates.
    public var point: SIMD3<Double>
    public var distance: Double

    public init(partID: UUID, triangle: Int, face: Int?, point: SIMD3<Double>, distance: Double) {
        self.partID = partID
        self.triangle = triangle
        self.face = face
        self.point = point
        self.distance = distance
    }
}

/// Ray picking against part meshes, with a bounding box check per part first.
public struct PartPicker: Sendable {
    struct Entry: Sendable {
        var id: UUID
        var geometry: PartGeometry
        var bounds: BoundingBox
    }

    let entries: [Entry]

    public init(parts: [Part]) {
        entries = parts.map { Entry(id: $0.id, geometry: $0.geometry, bounds: $0.geometry.bounds) }
    }

    public var partIDs: [UUID] { entries.map(\.id) }

    public func pick(_ ray: Ray, among visibleIDs: Set<UUID>? = nil) -> PickHit? {
        var nearest: PickHit?
        for entry in entries where visibleIDs?.contains(entry.id) ?? true {
            guard let boxDistance = Self.intersect(ray, entry.bounds), boxDistance < (nearest?.distance ?? .infinity) else {
                continue
            }
            let geometry = entry.geometry
            for triangle in 0..<geometry.triangleCount {
                let a = SIMD3<Double>(geometry.positions[Int(geometry.indices[triangle * 3])])
                let b = SIMD3<Double>(geometry.positions[Int(geometry.indices[triangle * 3 + 1])])
                let c = SIMD3<Double>(geometry.positions[Int(geometry.indices[triangle * 3 + 2])])
                if let distance = Self.intersect(ray, a, b, c), distance < (nearest?.distance ?? .infinity) {
                    nearest = PickHit(
                        partID: entry.id, triangle: triangle, face: nil, point: ray.point(at: distance), distance: distance
                    )
                }
            }
        }
        guard var hit = nearest, let entry = entries.first(where: { $0.id == hit.partID }) else { return nil }
        hit.face = entry.geometry.face(ofTriangle: hit.triangle)
        return hit
    }

    /// Möller–Trumbore, both sides. Returns the distance along the ray.
    static func intersect(_ ray: Ray, _ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) -> Double? {
        let edge1 = b - a
        let edge2 = c - a
        let p = simd_cross(ray.direction, edge2)
        let determinant = simd_dot(edge1, p)
        guard abs(determinant) > 1e-18 else { return nil }
        let inverse = 1 / determinant
        let t = ray.origin - a
        let u = simd_dot(t, p) * inverse
        guard u >= 0, u <= 1 else { return nil }
        let q = simd_cross(t, edge1)
        let v = simd_dot(ray.direction, q) * inverse
        guard v >= 0, u + v <= 1 else { return nil }
        let distance = simd_dot(edge2, q) * inverse
        return distance >= 0 ? distance : nil
    }

    /// Slab test. Returns the entry distance (0 if the ray starts inside).
    static func intersect(_ ray: Ray, _ box: BoundingBox) -> Double? {
        guard !box.isEmpty else { return nil }
        var near = 0.0
        var far = Double.infinity
        for axis in 0..<3 {
            let origin = ray.origin[axis]
            let direction = ray.direction[axis]
            if abs(direction) < 1e-15 {
                if origin < box.minimum[axis] || origin > box.maximum[axis] { return nil }
                continue
            }
            var entry = (box.minimum[axis] - origin) / direction
            var exit = (box.maximum[axis] - origin) / direction
            if entry > exit { swap(&entry, &exit) }
            near = max(near, entry)
            far = min(far, exit)
            if near > far { return nil }
        }
        return near
    }
}
