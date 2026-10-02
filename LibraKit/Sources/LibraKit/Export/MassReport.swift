import Foundation
import simd

/// Everything the exporters write, computed once from a document. SI units throughout.
public struct MassReport: Sendable {
    public struct GroupEntry: Sendable {
        public var name: String
        /// Group frame origin in the Libra frame.
        public var position: SIMD3<Double>
        /// Group frame axes in the Libra frame (columns).
        public var rotation: simd_double3x3
        /// In the group frame; inertia about the center of mass along the group axes.
        public var summary: MassSummary
        public var partNames: [String]
    }

    public struct PartEntry: Sendable {
        public var name: String
        public var path: [String]
        public var assignment: String
        /// In the Libra frame; nil while unassigned.
        public var properties: MassProperties?
    }

    public var modelName: String
    /// In the Libra frame.
    public var assembly: MassSummary
    public var groups: [GroupEntry]
    public var parts: [PartEntry]

    /// With no groups defined, the whole assembly is reported as one group in the Libra frame.
    public init(document: LibraDocument, modelName: String) {
        self.modelName = modelName
        let libraFrame = document.libraFrame
        assembly = MassSummary(parts: document.parts).expressed(in: libraFrame)

        let groups = document.groups.isEmpty
            ? [PartGroup(name: modelName, partIDs: document.parts.map(\.id), frame: libraFrame)]
            : document.groups
        self.groups = groups.map { group in
            let parts = document.parts(group.partIDs)
            let pose = group.frame.pose(relativeTo: libraFrame)
            return GroupEntry(
                name: group.name,
                position: pose.position,
                rotation: pose.rotation,
                summary: MassSummary(parts: parts).expressed(in: group.frame),
                partNames: parts.map(\.name)
            )
        }
        parts = document.parts.map { part in
            PartEntry(
                name: part.name,
                path: part.path,
                assignment: part.mass.kind.rawValue,
                properties: part.massProperties?.expressed(in: libraFrame)
            )
        }
    }
}

/// Number and name formatting shared by the exporters.
enum ExportFormat {
    static func number(_ value: Double) -> String {
        let text = String(format: "%.9g", value)
        return text == "-0" ? "0" : text
    }

    static func numbers(_ values: [Double]) -> String {
        values.map(number).joined(separator: " ")
    }

    /// MuJoCo `w x y z`, with w ≥ 0.
    static func quaternion(_ rotation: simd_double3x3) -> [Double] {
        let quaternion = simd_quatd(rotation)
        let sign = quaternion.real < 0 ? -1.0 : 1.0
        return [quaternion.real, quaternion.imag.x, quaternion.imag.y, quaternion.imag.z].map { $0 * sign }
    }

    /// URDF roll-pitch-yaw (fixed X, then Y, then Z: R = Rz(yaw) Ry(pitch) Rx(roll)).
    static func rollPitchYaw(_ rotation: simd_double3x3) -> [Double] {
        // simd is column-major: rotation[column][row]
        let pitch = asin(min(max(-rotation[0][2], -1), 1))
        if abs(cos(pitch)) < 1e-9 {
            // Gimbal lock: put everything into yaw
            return [0, pitch, atan2(-rotation[1][0], rotation[1][1])]
        }
        return [atan2(rotation[1][2], rotation[2][2]), pitch, atan2(rotation[0][1], rotation[0][0])]
    }

    /// Letters, digits, `_` and `-` only, and unique within the export.
    static func identifiers(for names: [String]) -> [String] {
        var used: Set<String> = []
        return names.map { name in
            var base = String(name.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") ? $0 : "_" })
            if base.isEmpty { base = "group" }
            var candidate = base
            var suffix = 2
            while used.contains(candidate) {
                candidate = "\(base)_\(suffix)"
                suffix += 1
            }
            used.insert(candidate)
            return candidate
        }
    }

    static func xmlEscaped(_ text: String) -> String {
        text.replacing("&", with: "&amp;").replacing("<", with: "&lt;").replacing(">", with: "&gt;")
            .replacing("\"", with: "&quot;").replacing("--", with: "- -")
    }
}
