/// Units for showing and entering values. Everything is stored in SI.
public struct DisplayUnits: Hashable, Sendable {
    public var length: LengthUnit
    public var mass: MassUnit
    public var inertia: InertiaUnit

    public static let standard = DisplayUnits(length: .millimeters, mass: .grams, inertia: .kilogramSquareMeters)

    public init(length: LengthUnit, mass: MassUnit, inertia: InertiaUnit) {
        self.length = length
        self.mass = mass
        self.inertia = inertia
    }
}

public protocol DisplayUnit: CaseIterable, Hashable, Identifiable, RawRepresentable, Sendable where RawValue == String {
    var symbol: String { get }
    /// How many SI units one of this unit is.
    var siPerUnit: Double { get }
}

extension DisplayUnit {
    public var id: String { rawValue }

    public func fromSI(_ value: Double) -> Double { value / siPerUnit }
    public func toSI(_ value: Double) -> Double { value * siPerUnit }
}

public enum LengthUnit: String, DisplayUnit {
    case millimeters, meters

    public var symbol: String { self == .millimeters ? "mm" : "m" }
    public var siPerUnit: Double { self == .millimeters ? 1e-3 : 1 }
}

public enum MassUnit: String, DisplayUnit {
    case grams, kilograms

    public var symbol: String { self == .grams ? "g" : "kg" }
    public var siPerUnit: Double { self == .grams ? 1e-3 : 1 }
}

public enum InertiaUnit: String, DisplayUnit {
    case kilogramSquareMeters, kilogramSquareMillimeters, gramSquareMillimeters

    public var symbol: String {
        switch self {
        case .kilogramSquareMeters: "kg·m²"
        case .kilogramSquareMillimeters: "kg·mm²"
        case .gramSquareMillimeters: "g·mm²"
        }
    }

    public var siPerUnit: Double {
        switch self {
        case .kilogramSquareMeters: 1
        case .kilogramSquareMillimeters: 1e-6
        case .gramSquareMillimeters: 1e-9
        }
    }
}
