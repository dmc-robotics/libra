/// How a part gets its mass.
public enum MassAssignment: Codable, Hashable, Sendable {
    case unassigned
    /// Weighed mass in kg, spread uniformly through the part's volume.
    case measured(Double)
    /// Datasheet values that ignore the geometry.
    case override(MassOverride)

    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case unassigned, measured, override

        public var id: Self { self }
    }

    public var kind: Kind {
        switch self {
        case .unassigned: .unassigned
        case .measured: .measured
        case .override: .override
        }
    }
}

/// Mass, center of mass and inertia entered by hand, expressed in `frame`.
public struct MassOverride: Codable, Hashable, Sendable {
    public var mass: Double
    /// In `frame` coordinates.
    public var centerOfMass: SIMD3<Double>
    /// About the center of mass, along `frame`'s axes.
    public var inertia: InertiaTensor
    public var frame: Frame
    /// Draw `frame` in the viewer even when it isn't being edited.
    public var showsFrame: Bool

    public init(mass: Double, centerOfMass: SIMD3<Double>, inertia: InertiaTensor, frame: Frame, showsFrame: Bool = false) {
        self.mass = mass
        self.centerOfMass = centerOfMass
        self.inertia = inertia
        self.frame = frame
        self.showsFrame = showsFrame
    }

    /// Converted to file coordinates.
    public var massProperties: MassProperties {
        MassProperties(
            mass: mass,
            centerOfMass: frame.filePoint(centerOfMass),
            inertia: inertia.expressed(inAxes: frame.rotation.transpose)
        )
    }
}
