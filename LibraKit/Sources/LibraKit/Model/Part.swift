import Foundation

/// One instance of a component from the STEP file, flattened to file coordinates.
public struct Part: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    /// Instance name, e.g. "Hub v3:1".
    public var name: String
    /// Shared by every instance of the same component, e.g. "Hub v3".
    public var definitionName: String
    /// Names of the enclosing assemblies, root first.
    public var path: [String]
    public var color: RGBColor?
    public var volumeProperties: VolumeProperties
    public var geometry: PartGeometry
    public var mass: MassAssignment

    public init(
        id: UUID = UUID(), name: String, definitionName: String, path: [String], color: RGBColor?,
        volumeProperties: VolumeProperties, geometry: PartGeometry, mass: MassAssignment = .unassigned
    ) {
        self.id = id
        self.name = name
        self.definitionName = definitionName
        self.path = path
        self.color = color
        self.volumeProperties = volumeProperties
        self.geometry = geometry
        self.mass = mass
    }

    /// Surface bodies and other shapes without a closed volume can't take a measured mass.
    public var hasVolume: Bool {
        volumeProperties.volume > VolumeProperties.minimumVolume
    }

    /// The part's mass properties in file coordinates, or nil while unassigned.
    public var massProperties: MassProperties? {
        switch mass {
        case .unassigned:
            nil
        case .measured(let mass):
            hasVolume ? MassProperties(measuredMass: mass, volumeProperties: volumeProperties) : nil
        case .override(let values):
            values.massProperties
        }
    }
}

/// Exact geometric properties at unit density (1 kg/m³), from the B-rep. File coordinates.
public struct VolumeProperties: Codable, Hashable, Sendable {
    /// Below this (1 mm³) a part is treated as having no volume.
    public static let minimumVolume = 1e-9

    public var volume: Double
    public var centroid: SIMD3<Double>
    /// About the centroid, file axes.
    public var unitDensityInertia: InertiaTensor

    public init(volume: Double, centroid: SIMD3<Double>, unitDensityInertia: InertiaTensor) {
        self.volume = volume
        self.centroid = centroid
        self.unitDensityInertia = unitDensityInertia
    }
}

public struct RGBColor: Codable, Hashable, Sendable {
    public var red: Float
    public var green: Float
    public var blue: Float

    public init(red: Float, green: Float, blue: Float) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}
