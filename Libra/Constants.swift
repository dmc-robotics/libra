import Foundation

/// UserDefaults keys and default values for Settings.
enum Preferences {
    static let lengthUnitKey = "lengthUnit"
    static let massUnitKey = "massUnit"
    static let inertiaUnitKey = "inertiaUnit"
}

enum Layout {
    static let sidebarMinWidth: CGFloat = 200
    static let sidebarIdealWidth: CGFloat = 240
    /// The viewer column's share of the window minimum. Not applied to the column itself: an explicit
    /// minimum there makes the split view loop too.
    static let detailMinWidth: CGFloat = 360
    static let inspectorMinWidth: CGFloat = 300
    static let inspectorIdealWidth: CGFloat = 340
    /// Room for the split view's dividers and insets.
    static let splitViewSlack: CGFloat = 60
    /// Must cover every column's minimum. If the window can get narrower than the columns need, SwiftUI's
    /// split view never settles and AppKit aborts ("more Update Constraints in Window passes than there are views").
    static let windowMinWidth: CGFloat = sidebarMinWidth + detailMinWidth + inspectorMinWidth + splitViewSlack
    static let windowMinHeight: CGFloat = 560
    static let defaultWindowWidth: CGFloat = 1300
    static let defaultWindowHeight: CGFloat = 820
    static let numberFieldWidth: CGFloat = 90
    static let unitLabelWidth: CGFloat = 40
    static let settingsWidth: CGFloat = 380
    static let exportSheetWidth: CGFloat = 640
    static let exportSheetHeight: CGFloat = 520
    static let statusBarHeight: CGFloat = 28
    /// How far inspector numbers may shrink to fit a narrow column.
    static let minimumTextScale: CGFloat = 0.75
}

enum Formatting {
    /// Significant digits shown for mass properties.
    static let significantDigits = 5
    /// Values this small relative to the largest in the same tensor are shown as 0.
    static let relativeNoise = 1e-9
}

enum ViewerStyle {
    static let defaultPartColor: SIMD4<Float> = [0.72, 0.74, 0.78, 1]
    static let assignedColor: SIMD4<Float> = [0.55, 0.75, 0.55, 1]
    static let unassignedColor: SIMD4<Float> = [0.95, 0.62, 0.30, 1]
    static let ungroupedColor: SIMD4<Float> = [0.80, 0.80, 0.80, 1]
    /// How strongly the accent color tints selected parts (0…1).
    static let selectionTint: Float = 0.55
    /// Colors for groups in "Color by Group" mode, reused in order.
    static let groupColors: [SIMD4<Float>] = [
        [0.36, 0.60, 0.92, 1], [0.92, 0.55, 0.30, 1], [0.45, 0.78, 0.45, 1], [0.86, 0.42, 0.62, 1],
        [0.62, 0.50, 0.88, 1], [0.90, 0.78, 0.32, 1], [0.35, 0.78, 0.78, 1], [0.70, 0.55, 0.40, 1]
    ]
    static let edgeColor: SIMD4<Float> = [0.08, 0.08, 0.10, 1]
    /// Viewer background in dark and light appearance.
    static let darkBackground: SIMD3<Double> = [0.22, 0.22, 0.24]
    static let lightBackground: SIMD3<Double> = [0.97, 0.97, 0.98]
    /// Mouse travel (points) before a press counts as a drag rather than a click.
    static let dragThreshold = 3.0
    /// Zoom exponent per line of mouse-wheel scroll (about 10% per notch).
    static let wheelZoomRate = 0.1
    static let sampleCount = 4
}
