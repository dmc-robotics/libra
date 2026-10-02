import Foundation
import simd

public enum ExportKind: String, CaseIterable, Identifiable, Sendable {
    case json, csv, mjcf, urdf

    public var id: Self { self }

    public var name: String {
        switch self {
        case .json: "JSON"
        case .csv: "CSV"
        case .mjcf: "MuJoCo MJCF"
        case .urdf: "URDF"
        }
    }

    public var fileExtension: String {
        switch self {
        case .json: "json"
        case .csv: "csv"
        case .mjcf: "xml"
        case .urdf: "urdf"
        }
    }

    public func text(for report: MassReport) -> String {
        switch self {
        case .json: JSONExporter.text(for: report)
        case .csv: CSVExporter.text(for: report)
        case .mjcf: MJCFExporter.text(for: report)
        case .urdf: URDFExporter.text(for: report)
        }
    }
}

enum JSONExporter {
    struct Document: Encodable {
        var generator = "Libra"
        var units = ["length": "m", "mass": "kg", "inertia": "kg*m^2"]
        var notes = "Assembly and parts are in the Libra frame. Each body's properties are in its own frame; its pose is relative to the Libra frame. Inertia is about the center of mass, as tensor entries (xy = -∫xy dm)."
        var assembly: Properties
        var bodies: [BodyEntry]
        var parts: [PartEntry]
    }

    struct Properties: Encodable {
        var mass: Double
        var centerOfMass: [Double]
        var inertia: InertiaTensor
        var partCount: Int
        var unassignedCount: Int

        init(_ summary: MassSummary) {
            mass = summary.properties.mass
            centerOfMass = [summary.properties.centerOfMass.x, summary.properties.centerOfMass.y, summary.properties.centerOfMass.z]
            inertia = summary.properties.inertia
            partCount = summary.partCount
            unassignedCount = summary.unassignedCount
        }
    }

    struct BodyEntry: Encodable {
        var name: String
        var position: [Double]
        /// Row-major; columns are the body axes in the Libra frame.
        var rotation: [[Double]]
        var quaternion: [Double]
        var properties: Properties
        var parts: [String]
    }

    struct PartEntry: Encodable {
        var name: String
        var path: [String]
        var assignment: String
        var mass: Double?
        var centerOfMass: [Double]?
        var inertia: InertiaTensor?
    }

    static func text(for report: MassReport) -> String {
        let document = Document(
            assembly: Properties(report.assembly),
            bodies: report.bodies.map { body in
                BodyEntry(
                    name: body.name,
                    position: [body.position.x, body.position.y, body.position.z],
                    rotation: (0..<3).map { row in (0..<3).map { column in body.rotation[column][row] } },
                    quaternion: ExportFormat.quaternion(body.rotation),
                    properties: Properties(body.summary),
                    parts: body.partNames
                )
            },
            parts: report.parts.map { part in
                PartEntry(
                    name: part.name,
                    path: part.path,
                    assignment: part.assignment,
                    mass: part.properties?.mass,
                    centerOfMass: part.properties.map { [$0.centerOfMass.x, $0.centerOfMass.y, $0.centerOfMass.z] },
                    inertia: part.properties?.inertia
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(document) else { return "{}" }
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}

enum CSVExporter {
    static let header = "kind,name,frame,mass_kg,com_x_m,com_y_m,com_z_m,ixx,iyy,izz,ixy,ixz,iyz,unassigned_parts"

    static func text(for report: MassReport) -> String {
        var lines = [header]
        lines.append(row("assembly", report.modelName, "libra", report.assembly.properties, report.assembly.unassignedCount))
        for body in report.bodies {
            lines.append(row("body", body.name, "body", body.summary.properties, body.summary.unassignedCount))
        }
        for part in report.parts {
            lines.append(row("part", part.name, "libra", part.properties, part.properties == nil ? 1 : 0))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func row(_ kind: String, _ name: String, _ frame: String, _ properties: MassProperties?, _ unassigned: Int) -> String {
        let values: [String] = if let properties {
            [properties.mass, properties.centerOfMass.x, properties.centerOfMass.y, properties.centerOfMass.z,
             properties.inertia.xx, properties.inertia.yy, properties.inertia.zz,
             properties.inertia.xy, properties.inertia.xz, properties.inertia.yz].map(ExportFormat.number)
        } else {
            Array(repeating: "", count: 10)
        }
        return ([kind, quoted(name), frame] + values + [String(unassigned)]).joined(separator: ",")
    }

    static func quoted(_ field: String) -> String {
        guard field.contains(where: { ",\"\n".contains($0) }) else { return field }
        return "\"" + field.replacing("\"", with: "\"\"") + "\""
    }
}

enum MJCFExporter {
    static func text(for report: MassReport) -> String {
        let names = ExportFormat.identifiers(for: report.bodies.map(\.name))
        var lines = [
            "<!-- Generated by Libra. SI units (m, kg, kg·m²). Body poses are relative to the Libra frame;",
            "     each inertial is in its body's frame. Add joints and nest bodies to build the kinematic tree. -->",
            "<mujoco model=\"\(ExportFormat.xmlEscaped(report.modelName))\">",
            "  <worldbody>"
        ]
        for (body, name) in zip(report.bodies, names) {
            let pose = "pos=\"\(ExportFormat.numbers(body.position.array))\" quat=\"\(ExportFormat.numbers(ExportFormat.quaternion(body.rotation)))\""
            lines.append("    <body name=\"\(name)\" \(pose)>")
            let properties = body.summary.properties
            if properties.mass > 0 {
                let inertia = properties.inertia
                lines.append(
                    "      <inertial pos=\"\(ExportFormat.numbers(properties.centerOfMass.array))\" mass=\"\(ExportFormat.number(properties.mass))\""
                        + " fullinertia=\"\(ExportFormat.numbers([inertia.xx, inertia.yy, inertia.zz, inertia.xy, inertia.xz, inertia.yz]))\"/>"
                )
            } else {
                lines.append("      <!-- no parts with an assigned mass -->")
            }
            if body.summary.unassignedCount > 0 {
                lines.append("      <!-- \(body.summary.unassignedCount) of \(body.summary.partCount) parts have no mass and are left out -->")
            }
            lines.append("    </body>")
        }
        lines += ["  </worldbody>", "</mujoco>"]
        return lines.joined(separator: "\n") + "\n"
    }
}

enum URDFExporter {
    static func text(for report: MassReport) -> String {
        let names = ExportFormat.identifiers(for: report.bodies.map(\.name))
        var lines = [
            "<?xml version=\"1.0\"?>",
            "<!-- Generated by Libra. SI units (m, kg, kg·m²). Each link's inertial is in its body frame.",
            "     URDF puts poses on joints, so each link's pose in the Libra frame is noted above it.",
            "     Libra doesn't write joints yet, so with several links this isn't a loadable robot on its own:",
            "     copy the <inertial> blocks into your URDF. -->",
            "<robot name=\"\(ExportFormat.identifiers(for: [report.modelName])[0])\">"
        ]
        for (body, name) in zip(report.bodies, names) {
            let rollPitchYaw = ExportFormat.numbers(ExportFormat.rollPitchYaw(body.rotation))
            lines.append("  <!-- \(ExportFormat.xmlEscaped(body.name)): pose in the Libra frame xyz=\"\(ExportFormat.numbers(body.position.array))\" rpy=\"\(rollPitchYaw)\" -->")
            if body.summary.unassignedCount > 0 {
                lines.append("  <!-- \(body.summary.unassignedCount) of \(body.summary.partCount) parts have no mass and are left out -->")
            }
            lines.append("  <link name=\"\(name)\">")
            let properties = body.summary.properties
            if properties.mass > 0 {
                let inertia = properties.inertia
                lines += [
                    "    <inertial>",
                    "      <origin xyz=\"\(ExportFormat.numbers(properties.centerOfMass.array))\" rpy=\"0 0 0\"/>",
                    "      <mass value=\"\(ExportFormat.number(properties.mass))\"/>",
                    "      <inertia ixx=\"\(ExportFormat.number(inertia.xx))\" ixy=\"\(ExportFormat.number(inertia.xy))\" ixz=\"\(ExportFormat.number(inertia.xz))\""
                        + " iyy=\"\(ExportFormat.number(inertia.yy))\" iyz=\"\(ExportFormat.number(inertia.yz))\" izz=\"\(ExportFormat.number(inertia.zz))\"/>",
                    "    </inertial>"
                ]
            }
            lines.append("  </link>")
        }
        lines.append("</robot>")
        return lines.joined(separator: "\n") + "\n"
    }
}

extension SIMD3<Double> {
    var array: [Double] { [x, y, z] }
}
