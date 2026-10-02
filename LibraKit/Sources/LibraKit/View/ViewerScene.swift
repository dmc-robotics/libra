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

    public init(
        parts: [ViewerPart] = [], highlightedFace: FeatureReference? = nil,
        highlightColor: SIMD4<Float> = [0, 0.5, 1, 1], markers: [Marker] = []
    ) {
        self.parts = parts
        self.highlightedFace = highlightedFace
        self.highlightColor = highlightColor
        self.markers = markers
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

/// Overlay symbols, drawn on top of the model at a constant screen size.
public enum Marker: Hashable, Sendable {
    case triad(Frame, emphasized: Bool)
    case centerOfMass(SIMD3<Double>)
    case snapPoint(SIMD3<Double>)
    case snapDirection(origin: SIMD3<Double>, direction: SIMD3<Double>)
    /// A highlighted edge.
    case snapEdge([SIMD3<Double>])
}
