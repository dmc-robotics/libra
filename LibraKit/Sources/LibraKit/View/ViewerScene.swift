import Foundation
import simd

/// Everything the 3D viewer draws, independent of how it draws it. The app builds this from the document
/// and the current selection; the renderer just draws it.
public struct ViewerScene: Sendable {
    public var parts: [ViewerPart]
    public var highlightedFace: FeatureReference?
    /// Selection tint, hovered face and snap markers.
    public var highlightColor: SIMD4<Float>
    public var markers: [Marker]
    public var tooltips: [ViewerTooltip]

    public init(
        parts: [ViewerPart] = [], highlightedFace: FeatureReference? = nil,
        highlightColor: SIMD4<Float> = [0, 0.5, 1, 1], markers: [Marker] = [], tooltips: [ViewerTooltip] = []
    ) {
        self.parts = parts
        self.highlightedFace = highlightedFace
        self.highlightColor = highlightColor
        self.markers = markers
        self.tooltips = tooltips
    }
}

public struct ViewerPart: Sendable {
    public var id: UUID
    public var geometry: PartGeometry
    public var color: SIMD4<Float>

    public init(id: UUID, geometry: PartGeometry, color: SIMD4<Float>) {
        self.id = id
        self.geometry = geometry
        self.color = color
    }
}

/// A face or edge of one part.
public struct FeatureReference: Hashable, Sendable {
    public var partID: UUID
    public var index: Int

    public init(partID: UUID, index: Int) {
        self.partID = partID
        self.index = index
    }
}

/// The Libra frame is drawn large; group frames small, so a frame that coincides with it still shows.
public enum TriadSize: Hashable, Sendable {
    case large, small
}

/// Overlay symbols, drawn on top of the model at a constant screen size.
public enum Marker: Hashable, Sendable {
    /// A coordinate frame; a selected one glows around its origin.
    case triad(Frame, size: TriadSize, selected: Bool)
    case centerOfMass(SIMD3<Double>)
    case snapPoint(SIMD3<Double>)
    case snapDirection(origin: SIMD3<Double>, direction: SIMD3<Double>)
    /// A highlighted edge.
    case snapEdge([SIMD3<Double>])
}

/// Text shown when the cursor rests on a point in the scene, such as a frame's origin.
public struct ViewerTooltip: Hashable, Sendable {
    public var point: SIMD3<Double>
    /// Half the width of the square around the point that shows the text, in viewport points.
    public var radius: Double
    public var text: String

    public init(point: SIMD3<Double>, radius: Double, text: String) {
        self.point = point
        self.radius = radius
        self.text = text
    }
}

/// Where a tooltip sits on screen. Tooltips whose points land on the same spot, like a group frame
/// still at the Libra frame's origin, share one region with a line each.
public struct TooltipRegion: Hashable, Sendable {
    /// Points closer than this on screen count as the same spot.
    public static let mergeDistance = 2.0

    public var center: SIMD2<Double>
    public var radius: Double
    public var text: String

    public static func regions(for tooltips: [ViewerTooltip], camera: OrthographicCamera) -> [TooltipRegion] {
        var regions: [TooltipRegion] = []
        for tooltip in tooltips {
            let center = camera.project(tooltip.point)
            if let index = regions.firstIndex(where: { simd_distance($0.center, center) < mergeDistance }) {
                regions[index].radius = max(regions[index].radius, tooltip.radius)
                regions[index].text += "\n" + tooltip.text
            } else {
                regions.append(TooltipRegion(center: center, radius: tooltip.radius, text: tooltip.text))
            }
        }
        return regions
    }
}
