import simd

/// Mass, center of mass and inertia about the center of mass, all in one coordinate system.
public struct MassProperties: Hashable, Sendable {
    public var mass: Double
    public var centerOfMass: SIMD3<Double>
    /// About the center of mass.
    public var inertia: InertiaTensor

    public static let zero = MassProperties(mass: 0, centerOfMass: .zero, inertia: .zero)

    public init(mass: Double, centerOfMass: SIMD3<Double>, inertia: InertiaTensor) {
        self.mass = mass
        self.centerOfMass = centerOfMass
        self.inertia = inertia
    }

    /// A weighed mass spread uniformly through the part's volume.
    public init(measuredMass: Double, volumeProperties: VolumeProperties) {
        let density = measuredMass / volumeProperties.volume
        self.init(
            mass: measuredMass,
            centerOfMass: volumeProperties.centroid,
            inertia: density * volumeProperties.unitDensityInertia
        )
    }

    /// Combines rigidly attached parts (parallel axis theorem).
    public static func combined(_ parts: [MassProperties]) -> MassProperties {
        let mass = parts.reduce(0) { $0 + $1.mass }
        guard mass > 0 else { return .zero }
        let centerOfMass = parts.reduce(SIMD3<Double>.zero) { $0 + $1.mass * $1.centerOfMass } / mass
        let inertia = parts.reduce(InertiaTensor.zero) { total, part in
            total + part.inertia + .pointMass(part.mass, at: part.centerOfMass - centerOfMass)
        }
        return MassProperties(mass: mass, centerOfMass: centerOfMass, inertia: inertia)
    }

    /// Re-expressed in `frame` (these properties must be in file coordinates).
    public func expressed(in frame: Frame) -> MassProperties {
        MassProperties(
            mass: mass,
            centerOfMass: frame.localPoint(centerOfMass),
            inertia: inertia.expressed(inAxes: frame.rotation)
        )
    }

    /// Inertia about the coordinate origin instead of the center of mass.
    public var inertiaAboutOrigin: InertiaTensor {
        inertia + .pointMass(mass, at: centerOfMass)
    }

    public func inertia(about reference: InertiaReference) -> InertiaTensor {
        switch reference {
        case .centerOfMass: inertia
        case .origin: inertiaAboutOrigin
        }
    }
}

/// The point an inertia tensor is taken about. Along the same axes either way.
public enum InertiaReference: String, CaseIterable, Identifiable, Sendable {
    case centerOfMass
    /// The origin of the frame the properties are expressed in.
    case origin

    public var id: Self { self }
}

/// Totals for a set of parts, with a count of the ones that couldn't contribute.
public struct MassSummary: Hashable, Sendable {
    /// In file coordinates.
    public var properties: MassProperties
    public var partCount: Int
    /// Parts with no mass yet, or a mass but no volume to spread it through.
    public var unassignedCount: Int

    public init(parts: [Part]) {
        let assigned = parts.compactMap(\.massProperties)
        properties = .combined(assigned)
        partCount = parts.count
        unassignedCount = parts.count - assigned.count
    }

    /// Re-expressed in `frame` (these totals must be in file coordinates). With no mass there's no
    /// center of mass to move, so the zero properties stay as they are.
    public func expressed(in frame: Frame) -> MassSummary {
        var copy = self
        if properties.mass > 0 {
            copy.properties = properties.expressed(in: frame)
        }
        return copy
    }
}
