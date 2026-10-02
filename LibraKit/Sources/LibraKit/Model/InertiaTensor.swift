import simd

/// A symmetric inertia tensor. Off-diagonal values are the tensor's entries (`xy = -∫xy dm`), which is
/// what MJCF `fullinertia` and URDF `<inertia>` expect.
public struct InertiaTensor: Codable, Hashable, Sendable {
    public var xx: Double
    public var yy: Double
    public var zz: Double
    public var xy: Double
    public var xz: Double
    public var yz: Double

    public static let zero = InertiaTensor(xx: 0, yy: 0, zz: 0, xy: 0, xz: 0, yz: 0)

    public init(xx: Double, yy: Double, zz: Double, xy: Double, xz: Double, yz: Double) {
        self.xx = xx
        self.yy = yy
        self.zz = zz
        self.xy = xy
        self.xz = xz
        self.yz = yz
    }

    public init(_ matrix: simd_double3x3) {
        self.init(
            xx: matrix[0, 0], yy: matrix[1, 1], zz: matrix[2, 2],
            // Average the mirrored entries to keep the result exactly symmetric
            xy: (matrix[1, 0] + matrix[0, 1]) / 2,
            xz: (matrix[2, 0] + matrix[0, 2]) / 2,
            yz: (matrix[2, 1] + matrix[1, 2]) / 2
        )
    }

    public var matrix: simd_double3x3 {
        simd_double3x3(rows: [
            SIMD3(xx, xy, xz),
            SIMD3(xy, yy, yz),
            SIMD3(xz, yz, zz)
        ])
    }

    public static func + (left: InertiaTensor, right: InertiaTensor) -> InertiaTensor {
        InertiaTensor(left.matrix + right.matrix)
    }

    public static func * (scale: Double, tensor: InertiaTensor) -> InertiaTensor {
        InertiaTensor(scale * tensor.matrix)
    }

    /// The same physical tensor expressed in axes rotated by `rotation` (columns are the new axes in old coordinates).
    public func expressed(inAxes rotation: simd_double3x3) -> InertiaTensor {
        InertiaTensor(rotation.transpose * matrix * rotation)
    }

    /// The inertia of a point mass `mass` at `offset` (parallel axis theorem term).
    public static func pointMass(_ mass: Double, at offset: SIMD3<Double>) -> InertiaTensor {
        let identity = simd_double3x3(diagonal: SIMD3(repeating: 1))
        let outer = simd_double3x3(columns: (offset * offset.x, offset * offset.y, offset * offset.z))
        return InertiaTensor(mass * (simd_length_squared(offset) * identity - outer))
    }
}
