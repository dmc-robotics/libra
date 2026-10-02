import simd

/// A point or direction taken from a CAD feature under the cursor.
public struct Snap: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case vertex, circleCenter, axisCenter, axisPoint, sphereCenter, faceCenter, surfacePoint
        case lineDirection, circleNormal, axisDirection, faceNormal

        public var name: String {
            switch self {
            case .vertex: "Vertex"
            case .circleCenter: "Circle center"
            case .axisCenter: "Cylinder center"
            case .axisPoint: "Point on axis"
            case .sphereCenter: "Sphere center"
            case .faceCenter: "Face center"
            case .surfacePoint: "Point on surface"
            case .lineDirection: "Edge direction"
            case .circleNormal: "Circle axis"
            case .axisDirection: "Axis"
            case .faceNormal: "Face normal"
            }
        }
    }

    public var kind: Kind
    public var point: SIMD3<Double>
    /// Set for direction snaps.
    public var direction: SIMD3<Double>?
    public var face: FeatureReference?
    public var edge: FeatureReference?
}

/// Turns a pick hit into the feature the user most likely means. Corners and edges win when the
/// cursor is within `tolerance` points of them; otherwise the face's own feature applies.
public struct Snapper {
    /// Viewport points.
    public static let defaultTolerance = 8.0

    let camera: OrthographicCamera
    let cursor: SIMD2<Double>
    let tolerance: Double

    public init(camera: OrthographicCamera, cursor: SIMD2<Double>, tolerance: Double = Snapper.defaultTolerance) {
        self.camera = camera
        self.cursor = cursor
        self.tolerance = tolerance
    }

    public func originSnap(for hit: PickHit, in geometry: PartGeometry) -> Snap? {
        guard let face = hit.face else { return nil }
        let faceReference = FeatureReference(partID: hit.partID, index: face)
        let feature = geometry.faces[face]

        if let vertex = nearestVertex(of: face, in: geometry) {
            return Snap(kind: .vertex, point: vertex, face: faceReference)
        }
        if let edge = nearestEdge(of: face, in: geometry, where: { $0.kind == .circle }) {
            return Snap(
                kind: .circleCenter, point: geometry.edges[edge].center, face: faceReference,
                edge: FeatureReference(partID: hit.partID, index: edge)
            )
        }
        switch feature.kind {
        case .cylinder, .cone, .torus:
            // The face's center on its axis (halfway along it) when the cursor is level with it, else anywhere on the axis
            let onAxis = feature.center + feature.direction * simd_dot(hit.point - feature.center, feature.direction)
            if simd_distance(camera.project(onAxis), camera.project(feature.center)) <= tolerance {
                return Snap(kind: .axisCenter, point: feature.center, face: faceReference)
            }
            return Snap(kind: .axisPoint, point: onAxis, face: faceReference)
        case .sphere:
            return Snap(kind: .sphereCenter, point: feature.center, face: faceReference)
        case .plane:
            return Snap(kind: .faceCenter, point: feature.center, face: faceReference)
        case .other:
            return Snap(kind: .surfacePoint, point: hit.point, face: faceReference)
        }
    }

    public func directionSnap(for hit: PickHit, in geometry: PartGeometry) -> Snap? {
        guard let face = hit.face else { return nil }
        let faceReference = FeatureReference(partID: hit.partID, index: face)
        let feature = geometry.faces[face]

        if let edge = nearestEdge(of: face, in: geometry, where: { $0.kind == .line || $0.kind == .circle }) {
            let edgeFeature = geometry.edges[edge]
            let points = geometry.points(ofEdge: edge)
            let middle = SIMD3<Double>(points[points.startIndex + points.count / 2])
            return Snap(
                kind: edgeFeature.kind == .line ? .lineDirection : .circleNormal,
                point: edgeFeature.kind == .line ? middle : edgeFeature.center,
                direction: edgeFeature.direction,
                face: faceReference,
                edge: FeatureReference(partID: hit.partID, index: edge)
            )
        }
        switch feature.kind {
        case .cylinder, .cone, .torus:
            return Snap(kind: .axisDirection, point: feature.center, direction: feature.direction, face: faceReference)
        case .plane:
            return Snap(kind: .faceNormal, point: feature.center, direction: feature.direction, face: faceReference)
        case .sphere, .other:
            return nil
        }
    }

    // MARK: Screen-space proximity

    private func screenDistance(to point: SIMD3<Double>) -> Double {
        simd_distance(camera.project(point), cursor)
    }

    private func nearestVertex(of face: Int, in geometry: PartGeometry) -> SIMD3<Double>? {
        // Corners of this face: the ends of its edges
        var best: (point: SIMD3<Double>, distance: Double)?
        for edge in geometry.edgeIndices(ofFace: face) {
            let points = geometry.points(ofEdge: Int(edge))
            guard let first = points.first, let last = points.last else { continue }
            for point in [first, last].map(SIMD3<Double>.init) {
                let distance = screenDistance(to: point)
                if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                    best = (point, distance)
                }
            }
        }
        // Only report it if it's a real topological vertex (closed circles have an endpoint that isn't one)
        guard let candidate = best?.point else { return nil }
        let isVertex = geometry.vertices.contains { simd_distance(SIMD3<Double>($0), candidate) < 1e-9 }
        return isVertex ? candidate : nil
    }

    private func nearestEdge(of face: Int, in geometry: PartGeometry, where include: (EdgeFeature) -> Bool) -> Int? {
        var best: (edge: Int, distance: Double)?
        for edgeIndex in geometry.edgeIndices(ofFace: face).map(Int.init) where include(geometry.edges[edgeIndex]) {
            let screenPoints = geometry.points(ofEdge: edgeIndex).map { camera.project(SIMD3<Double>($0)) }
            for (start, end) in zip(screenPoints, screenPoints.dropFirst()) {
                let distance = Self.distance(from: cursor, toSegment: start, end)
                if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                    best = (edgeIndex, distance)
                }
            }
        }
        return best?.edge
    }

    static func distance(from point: SIMD2<Double>, toSegment start: SIMD2<Double>, _ end: SIMD2<Double>) -> Double {
        let segment = end - start
        let lengthSquared = simd_length_squared(segment)
        guard lengthSquared > 0 else { return simd_distance(point, start) }
        let fraction = min(max(simd_dot(point - start, segment) / lengthSquared, 0), 1)
        return simd_distance(point, start + segment * fraction)
    }
}
