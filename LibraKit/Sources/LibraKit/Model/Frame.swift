import simd

/// A coordinate frame (origin + right-handed orthonormal axes) expressed in file coordinates.
public struct Frame: Codable, Hashable, Sendable {
    public var origin: SIMD3<Double>
    public var xAxis: SIMD3<Double>
    public var yAxis: SIMD3<Double>
    public var zAxis: SIMD3<Double>

    public static let file = Frame(origin: .zero, xAxis: [1, 0, 0], yAxis: [0, 1, 0], zAxis: [0, 0, 1])

    public init(origin: SIMD3<Double>, xAxis: SIMD3<Double>, yAxis: SIMD3<Double>, zAxis: SIMD3<Double>) {
        self.origin = origin
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.zAxis = zAxis
    }

    public init(origin: SIMD3<Double>, rotation: simd_double3x3) {
        self.init(origin: origin, xAxis: rotation.columns.0, yAxis: rotation.columns.1, zAxis: rotation.columns.2)
    }

    /// Columns are the frame's axes in file coordinates, so `rotation * local = file direction`.
    public var rotation: simd_double3x3 {
        simd_double3x3(columns: (xAxis, yAxis, zAxis))
    }

    public func axis(_ axis: FrameAxis) -> SIMD3<Double> {
        switch axis {
        case .x: xAxis
        case .y: yAxis
        case .z: zAxis
        }
    }

    public func localPoint(_ filePoint: SIMD3<Double>) -> SIMD3<Double> {
        rotation.transpose * (filePoint - origin)
    }

    public func localDirection(_ fileDirection: SIMD3<Double>) -> SIMD3<Double> {
        rotation.transpose * fileDirection
    }

    public func filePoint(_ localPoint: SIMD3<Double>) -> SIMD3<Double> {
        origin + rotation * localPoint
    }

    public func fileDirection(_ localDirection: SIMD3<Double>) -> SIMD3<Double> {
        rotation * localDirection
    }

    /// This frame's pose relative to `parent`: origin in parent coordinates and rotation from this frame to the parent.
    public func pose(relativeTo parent: Frame) -> (position: SIMD3<Double>, rotation: simd_double3x3) {
        (parent.localPoint(origin), parent.rotation.transpose * rotation)
    }

    /// Rotates the axes by a quarter turn about one of the frame's own axes. Positive is counterclockwise looking down the axis.
    public func rotatedQuarterTurn(about axis: FrameAxis, clockwise: Bool = false) -> Frame {
        let angle = (clockwise ? -1.0 : 1.0) * Double.pi / 2
        let turn = simd_quatd(angle: angle, axis: self.axis(axis))
        return Frame(origin: origin, rotation: Frame.snapped(simd_double3x3(turn) * rotation))
    }

    /// Points `axis` along `direction` using the smallest rotation, so the other axes move as little as possible.
    public func aligning(_ axis: FrameAxis, to direction: SIMD3<Double>) -> Frame {
        let target = simd_normalize(direction)
        let current = self.axis(axis)
        let turn: simd_quatd
        if simd_dot(current, target) < -0.999_999 {
            // Opposite: any half turn about a perpendicular axis works; use the next frame axis
            turn = simd_quatd(angle: .pi, axis: self.axis(axis.next))
        } else {
            turn = simd_quatd(from: current, to: target)
        }
        return Frame(origin: origin, rotation: Frame.orthonormalized(simd_double3x3(turn) * rotation))
    }

    public func flipped(_ axis: FrameAxis) -> Frame {
        // Reversing one axis alone would make the frame left-handed, so turn half way about the next axis instead
        Frame(origin: origin, rotation: simd_double3x3(simd_quatd(angle: .pi, axis: self.axis(axis.next))) * rotation)
            .snappedIfNearlyExact()
    }

    public func moved(to origin: SIMD3<Double>) -> Frame {
        Frame(origin: origin, xAxis: xAxis, yAxis: yAxis, zAxis: zAxis)
    }

    private func snappedIfNearlyExact() -> Frame {
        Frame(origin: origin, rotation: Frame.snapped(rotation))
    }

    /// Cleans up rounding noise so quarter turns of an axis-aligned frame stay exactly axis-aligned.
    static func snapped(_ matrix: simd_double3x3) -> simd_double3x3 {
        func clean(_ value: Double) -> Double {
            for exact in [-1.0, 0.0, 1.0] where abs(value - exact) < 1e-12 {
                return exact
            }
            return value
        }
        func clean(_ column: SIMD3<Double>) -> SIMD3<Double> {
            SIMD3(clean(column.x), clean(column.y), clean(column.z))
        }
        return orthonormalized(simd_double3x3(columns: (clean(matrix.columns.0), clean(matrix.columns.1), clean(matrix.columns.2))))
    }

    static func orthonormalized(_ matrix: simd_double3x3) -> simd_double3x3 {
        let x = simd_normalize(matrix.columns.0)
        let z = simd_normalize(simd_cross(x, matrix.columns.1))
        let y = simd_cross(z, x)
        return simd_double3x3(columns: (x, y, z))
    }
}

public enum FrameAxis: Int, CaseIterable, Codable, Sendable {
    case x, y, z

    public var next: FrameAxis {
        FrameAxis(rawValue: (rawValue + 1) % 3)!
    }

    public var name: String {
        switch self {
        case .x: "X"
        case .y: "Y"
        case .z: "Z"
        }
    }
}
