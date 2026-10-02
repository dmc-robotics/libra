import LibraKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(Preferences.lengthUnitKey) private var length = DisplayUnits.standard.length
    @AppStorage(Preferences.massUnitKey) private var mass = DisplayUnits.standard.mass
    @AppStorage(Preferences.inertiaUnitKey) private var inertia = DisplayUnits.standard.inertia

    var body: some View {
        Form {
            Section {
                picker("Length", selection: $length)
                picker("Mass", selection: $mass)
                picker("Inertia", selection: $inertia)
            } footer: {
                Text("For display and entry only. Files and exports are always in SI units.")
            }
        }
        .formStyle(.grouped)
        .frame(width: Layout.settingsWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func picker<Unit: DisplayUnit>(_ title: String, selection: Binding<Unit>) -> some View where Unit.AllCases: RandomAccessCollection {
        Picker(title, selection: selection) {
            ForEach(Unit.allCases) { unit in
                Text(unit.symbol).tag(unit)
            }
        }
    }
}
