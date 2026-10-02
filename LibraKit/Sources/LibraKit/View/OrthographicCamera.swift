import simd

/// An orthographic view of the model. Viewport points have their origin at the bottom left, y up (AppKit's default).
public struct OrthographicCamera: Equatable, Sendable {
    /// Columns: right, up, back (toward the viewer), in file coordinates.
    public var orientation: simd_double3x3
    /// The file point at the middle of the viewport.
    public var center: SIMD3<Double>
    /// World height (meters) visible in the viewport.
    public var viewHeight: Double
    public var viewportSize: SIMD2<Double>
    /// Sets the depth range so the whole model is between the clipping planes.
    public var sceneBounds: BoundingBox

    /// Radians per point of mouse drag.
    public static let orbitSensitivity = 0.008
    static let fitMargin = 1.15
    static let minimumViewHeight = 1e-5

    public init(
        orientation: simd_double3x3 = StandardView.isometric.orientation(in: .file),
        center: SIMD3<Double> = .zero,
        viewHeight: Double = 1,
        viewportSize: SIMD2<Double> = [800, 600],
        sceneBounds: BoundingBox = BoundingBox(minimum: SIMD3(repeating: -1), maximum: SIMD3(repeating: 1))
    ) {
        self.orientation = orientation
        self.center = center
        self.viewHeight = viewHeight
        self.viewportSize = viewportSize
        self.sceneBounds = sceneBounds
    }

    public var right: SIMD3<Double> { orientation.columns.0 }
    public var up: SIMD3<Double> { orientation.columns.1 }
    public var back: SIMD3<Double> { orientation.columns.2 }

    var aspect: Double { viewportSize.y > 0 ? viewportSize.x / viewportSize.y : 1 }
    var halfHeight: Double { viewHeight / 2 }
    var halfWidth: Double { halfHeight * aspect }

    /// Meters per viewport point.
    public var worldPerPoint: Double { viewportSize.y > 0 ? viewHeight / viewportSize.y : 0 }

    // The eye sits far enough back that the whole model is in front of it
    var eyeDistance: Double {
        let radius = sceneBounds.isEmpty ? 1 : sceneBounds.diagonal / 2
        let offset = sceneBounds.isEmpty ? 0 : simd_distance(center, sceneBounds.center)
        return 2 * (radius + offset) + 1e-3
    }

    var eye: SIMD3<Double> { center + back * eyeDistance }

    // MARK: Matrices

    /// File → clip space for Metal: depth 0 at the eye, 1 at twice the eye distance.
    public var viewProjectionMatrix: simd_float4x4 {
        let far = 2 * eyeDistance
        let rotation = orientation.transpose
        let translation = -(rotation * eye)
        let view = simd_double4x4(columns: (
            SIMD4(rotation.columns.0, 0),
            SIMD4(rotation.columns.1, 0),
            SIMD4(rotation.columns.2, 0),
            SIMD4(translation, 1)
        ))
        let projection = simd_double4x4(rows: [
            SIMD4(1 / halfWidth, 0, 0, 0),
            SIMD4(0, 1 / halfHeight, 0, 0),
            SIMD4(0, 0, -1 / far, 0),
            SIMD4(0, 0, 0, 1)
        ])
        let combined = projection * view
        return simd_float4x4(columns: (
            SIMD4<Float>(combined.columns.0), SIMD4<Float>(combined.columns.1),
            SIMD4<Float>(combined.columns.2), SIMD4<Float>(combined.columns.3)
        ))
    }

    // MARK: Screen ↔ world

    func normalized(_ point: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(2 * point.x / viewportSize.x - 1, 2 * point.y / viewportSize.y - 1)
    }

    /// The file point under `point` on the plane through `center` facing the viewer.
    public func pointOnViewPlane(_ point: SIMD2<Double>) -> SIMD3<Double> {
        let ndc = normalized(point)
        return center + right * (ndc.x * halfWidth) + up * (ndc.y * halfHeight)
    }

    public func ray(through point: SIMD2<Double>) -> Ray {
        Ray(origin: pointOnViewPlane(point) + back * eyeDistance, direction: -back)
    }

    /// Viewport position of a file point.
    public func project(_ point: SIMD3<Double>) -> SIMD2<Double> {
        let offset = point - center
        let ndc = SIMD2(simd_dot(offset, right) / halfWidth, simd_dot(offset, up) / halfHeight)
        return SIMD2((ndc.x + 1) / 2 * viewportSize.x, (ndc.y + 1) / 2 * viewportSize.y)
    }

    // MARK: Navigation

    /// Turntable orbit: horizontal drags turn about `upAxis`, vertical drags tilt about the screen's horizontal axis.
    public mutating func orbit(by delta: SIMD2<Double>, around pivot: SIMD3<Double>, upAxis: SIMD3<Double>) {
        let turn = simd_quatd(angle: -delta.x * Self.orbitSensitivity, axis: simd_normalize(upAxis))
        let tilt = simd_quatd(angle: delta.y * Self.orbitSensitivity, axis: right)
        let rotation = simd_double3x3(turn * tilt)
        orientation = Frame.orthonormalized(rotation * orientation)
        center = pivot + rotation * (center - pivot)
    }

    /// Moves the view so the model follows the cursor.
    public mutating func pan(by delta: SIMD2<Double>) {
        center -= (right * delta.x + up * delta.y) * worldPerPoint
    }

    /// Zooms by `factor` (< 1 zooms in) keeping the point under `point` fixed.
    public mutating func zoom(by factor: Double, at point: SIMD2<Double>) {
        let before = pointOnViewPlane(point)
        viewHeight = max(viewHeight * factor, Self.minimumViewHeight)
        center += before - pointOnViewPlane(point)
    }

    /// Centers and scales the view so `bounds` fills it.
    public mutating func fit(_ bounds: BoundingBox) {
        guard !bounds.isEmpty else { return }
        center = bounds.center
        var halfExtent = SIMD2<Double>.zero
        for corner in bounds.corners {
            let offset = corner - center
            halfExtent = simd_max(halfExtent, SIMD2(abs(simd_dot(offset, right)), abs(simd_dot(offset, up))))
        }
        viewHeight = max(2 * max(halfExtent.y, halfExtent.x / aspect) * Self.fitMargin, Self.minimumViewHeight)
    }

    public mutating func look(from view: StandardView, in frame: Frame) {
        orientation = view.orientation(in: frame)
    }
}

public struct Ray: Hashable, Sendable {
    public var origin: SIMD3<Double>
    /// Unit length.
    public var direction: SIMD3<Double>

    public init(origin: SIMD3<Double>, direction: SIMD3<Double>) {
        self.origin = origin
        self.direction = simd_normalize(direction)
    }

    public func point(at distance: Double) -> SIMD3<Double> {
        origin + direction * distance
    }
}

/// Named views, with Z up in the given frame (the robotics convention).
public enum StandardView: String, CaseIterable, Sendable {
    case front, back, left, right, top, bottom, isometric

    public var name: String {
        switch self {
        case .isometric: "Isometric"
        default: rawValue.capitalized
        }
    }

    /// Camera orientation (columns right, up, back) in file coordinates.
    public func orientation(in frame: Frame) -> simd_double3x3 {
        let (back, up): (SIMD3<Double>, SIMD3<Double>) = switch self {
        case .front: ([0, -1, 0], [0, 0, 1])
        case .back: ([0, 1, 0], [0, 0, 1])
        case .left: ([-1, 0, 0], [0, 0, 1])
        case .right: ([1, 0, 0], [0, 0, 1])
        case .top: ([0, 0, 1], [0, 1, 0])
        case .bottom: ([0, 0, -1], [0, 1, 0])
        case .isometric: (simd_normalize([1, -1, 1]), [0, 0, 1])
        }
        let fileBack = frame.fileDirection(back)
        let right = simd_normalize(simd_cross(frame.fileDirection(up), fileBack))
        return simd_double3x3(columns: (right, simd_cross(fileBack, right), fileBack))
    }
}
