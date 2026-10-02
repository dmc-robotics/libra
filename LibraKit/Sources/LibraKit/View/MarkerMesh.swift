import simd

/// Matches the `MarkerVertex` struct in the app's Metal shaders (Shaders.swift).
public struct MarkerVertex: Sendable {
    public var position: SIMD3<Float>
    public var color: SIMD4<Float>
}

/// Builds flat, screen-facing triangles for markers. Sizes are in viewport points, so markers keep
/// their size as the view zooms.
public struct MarkerMesh {
    public enum Style {
        public static let triadLength = 60.0
        public static let emphasizedTriadLength = 80.0
        public static let lineWidth = 2.5
        public static let emphasizedLineWidth = 3.5
        public static let arrowLength = 10.0
        public static let arrowWidth = 8.0
        public static let centerOfMassRadius = 8.0
        public static let snapRadius = 7.0
        public static let snapDirectionLength = 120.0
        static let circleSegments = 32

        public static let xColor: SIMD4<Float> = [0.90, 0.22, 0.20, 1]
        public static let yColor: SIMD4<Float> = [0.20, 0.72, 0.25, 1]
        public static let zColor: SIMD4<Float> = [0.22, 0.45, 1.00, 1]
        public static let dark: SIMD4<Float> = [0.08, 0.08, 0.08, 1]
        public static let light: SIMD4<Float> = [1, 1, 1, 1]
    }

    let camera: OrthographicCamera
    let snapColor: SIMD4<Float>
    public private(set) var vertices: [MarkerVertex] = []

    public init(markers: [Marker], camera: OrthographicCamera, snapColor: SIMD4<Float>) {
        self.camera = camera
        self.snapColor = snapColor
        for marker in markers {
            add(marker)
        }
    }

    private var scale: Double { camera.worldPerPoint }

    private mutating func add(_ marker: Marker) {
        switch marker {
        case .triad(let frame, let emphasized):
            let length = (emphasized ? Style.emphasizedTriadLength : Style.triadLength) * scale
            let width = emphasized ? Style.emphasizedLineWidth : Style.lineWidth
            let colors = [Style.xColor, Style.yColor, Style.zColor]
            for axis in FrameAxis.allCases {
                arrow(from: frame.origin, to: frame.origin + frame.axis(axis) * length, width: width, color: colors[axis.rawValue])
            }
            disc(at: frame.origin, radius: width * 1.2, color: Style.dark)
        case .centerOfMass(let point):
            // The usual CG symbol: a circle in alternating dark and light quarters
            disc(at: point, radius: Style.centerOfMassRadius + 1.5, color: Style.dark)
            for quarter in 0..<4 {
                sector(at: point, radius: Style.centerOfMassRadius, quarter: quarter, color: quarter.isMultiple(of: 2) ? Style.dark : Style.light)
            }
        case .snapPoint(let point):
            ring(at: point, radius: Style.snapRadius, width: 2.5, color: snapColor)
            disc(at: point, radius: 2, color: snapColor)
        case .snapDirection(let origin, let direction):
            let half = Style.snapDirectionLength / 2 * scale
            let unit = simd_normalize(direction)
            arrow(from: origin - unit * half, to: origin + unit * half, width: Style.lineWidth, color: snapColor)
            disc(at: origin, radius: 3, color: snapColor)
        case .snapEdge(let points):
            for (start, end) in zip(points, points.dropFirst()) {
                line(from: start, to: end, width: Style.lineWidth, color: snapColor)
            }
        }
    }

    // MARK: Primitives

    private mutating func triangle(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>, _ color: SIMD4<Float>) {
        for point in [a, b, c] {
            vertices.append(MarkerVertex(position: SIMD3<Float>(point), color: color))
        }
    }

    /// A screen-space direction perpendicular to the segment, in file coordinates (zero if the segment points at the viewer).
    private func perpendicular(_ start: SIMD3<Double>, _ end: SIMD3<Double>) -> SIMD3<Double> {
        let delta = end - start
        let onScreen = SIMD2(simd_dot(delta, camera.right), simd_dot(delta, camera.up))
        guard simd_length(onScreen) > 1e-12 else { return .zero }
        let normal = simd_normalize(SIMD2(-onScreen.y, onScreen.x))
        return camera.right * normal.x + camera.up * normal.y
    }

    private mutating func line(from start: SIMD3<Double>, to end: SIMD3<Double>, width: Double, color: SIMD4<Float>) {
        let offset = perpendicular(start, end) * (width / 2 * scale)
        triangle(start - offset, end - offset, end + offset, color)
        triangle(start - offset, end + offset, start + offset, color)
    }

    private mutating func arrow(from start: SIMD3<Double>, to end: SIMD3<Double>, width: Double, color: SIMD4<Float>) {
        let side = perpendicular(start, end)
        let screenLength = simd_length(SIMD2(simd_dot(end - start, camera.right), simd_dot(end - start, camera.up)))
        guard side != .zero, screenLength > 1e-12 else {
            // Pointing straight at the viewer: show a dot instead
            disc(at: end, radius: width * 1.5, color: color)
            return
        }
        let direction = (end - start) / screenLength
        let headLength = Style.arrowLength * scale
        let shaftEnd = end - direction * min(headLength, screenLength)
        line(from: start, to: shaftEnd, width: width, color: color)
        let halfWidth = Style.arrowWidth / 2 * scale
        triangle(shaftEnd - side * halfWidth, end, shaftEnd + side * halfWidth, color)
    }

    private func circlePoint(_ center: SIMD3<Double>, _ radius: Double, _ angle: Double) -> SIMD3<Double> {
        center + (camera.right * cos(angle) + camera.up * sin(angle)) * (radius * scale)
    }

    private mutating func disc(at center: SIMD3<Double>, radius: Double, color: SIMD4<Float>) {
        let count = Style.circleSegments
        for index in 0..<count {
            let start = Double(index) / Double(count) * 2 * .pi
            let end = Double(index + 1) / Double(count) * 2 * .pi
            triangle(center, circlePoint(center, radius, start), circlePoint(center, radius, end), color)
        }
    }

    private mutating func sector(at center: SIMD3<Double>, radius: Double, quarter: Int, color: SIMD4<Float>) {
        let count = Style.circleSegments / 4
        for index in 0..<count {
            let start = (Double(quarter) + Double(index) / Double(count)) * .pi / 2
            let end = (Double(quarter) + Double(index + 1) / Double(count)) * .pi / 2
            triangle(center, circlePoint(center, radius, start), circlePoint(center, radius, end), color)
        }
    }

    private mutating func ring(at center: SIMD3<Double>, radius: Double, width: Double, color: SIMD4<Float>) {
        let count = Style.circleSegments
        let inner = radius - width / 2
        let outer = radius + width / 2
        for index in 0..<count {
            let start = Double(index) / Double(count) * 2 * .pi
            let end = Double(index + 1) / Double(count) * 2 * .pi
            triangle(circlePoint(center, inner, start), circlePoint(center, outer, start), circlePoint(center, outer, end), color)
            triangle(circlePoint(center, inner, start), circlePoint(center, outer, end), circlePoint(center, inner, end), color)
        }
    }
}
