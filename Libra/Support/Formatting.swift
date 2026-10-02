import AppKit
import LibraKit
import SwiftUI

/// The display units chosen in Settings.
@propertyWrapper
struct DisplayUnitsSetting: DynamicProperty {
    @AppStorage(Preferences.lengthUnitKey) private var length = DisplayUnits.standard.length
    @AppStorage(Preferences.massUnitKey) private var mass = DisplayUnits.standard.mass
    @AppStorage(Preferences.inertiaUnitKey) private var inertia = DisplayUnits.standard.inertia

    var wrappedValue: DisplayUnits {
        DisplayUnits(length: length, mass: mass, inertia: inertia)
    }
}

extension Formatting {
    /// Plain notation for everyday magnitudes, scientific for very large or small ones.
    static func number(_ value: Double) -> String {
        let magnitude = abs(value)
        if value == 0 || (magnitude >= 1e-3 && magnitude < 1e7) {
            return value.formatted(.number.precision(.significantDigits(1...significantDigits)))
        }
        return value.formatted(.number.notation(.scientific).precision(.significantDigits(1...significantDigits)))
    }

    static func vector(_ value: SIMD3<Double>) -> String {
        "(\(number(value.x)), \(number(value.y)), \(number(value.z)))"
    }

    /// A plain-text block for the clipboard.
    static func summary(_ properties: MassProperties, title: String, units: DisplayUnits) -> String {
        let inertia = properties.inertia
        let value = { units.inertia.fromSI($0) }
        return """
        \(title)
        Mass: \(number(units.mass.fromSI(properties.mass))) \(units.mass.symbol)
        Center of mass: \(vector(properties.centerOfMass / units.length.siPerUnit)) \(units.length.symbol)
        Inertia about COM (\(units.inertia.symbol)):
          Ixx \(number(value(inertia.xx)))  Ixy \(number(value(inertia.xy)))  Ixz \(number(value(inertia.xz)))
          Iyx \(number(value(inertia.xy)))  Iyy \(number(value(inertia.yy)))  Iyz \(number(value(inertia.yz)))
          Izx \(number(value(inertia.xz)))  Izy \(number(value(inertia.yz)))  Izz \(number(value(inertia.zz)))
        """
    }
}

extension NSColor {
    var simdColor: SIMD4<Float> {
        let color = usingColorSpace(.sRGB) ?? self
        return SIMD4(Float(color.redComponent), Float(color.greenComponent), Float(color.blueComponent), 1)
    }
}

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
