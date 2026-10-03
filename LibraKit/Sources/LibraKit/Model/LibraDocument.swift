import Foundation

/// The contents of a .libra file: geometry from one STEP import plus everything the user assigned.
public struct LibraDocument: Codable, Hashable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var parts: [Part]
    public var groups: [PartGroup]
    /// The reference frame for totals, display and export. Starts as the STEP file's frame.
    public var libraFrame: Frame

    public init(parts: [Part] = [], groups: [PartGroup] = [], libraFrame: Frame = .file) {
        formatVersion = Self.currentFormatVersion
        self.parts = parts
        self.groups = groups
        self.libraFrame = libraFrame
    }

    public var isEmpty: Bool { parts.isEmpty }

    public func part(_ id: UUID) -> Part? {
        parts.first { $0.id == id }
    }

    public func parts(_ ids: some Sequence<UUID>) -> [Part] {
        let wanted = Set(ids)
        return parts.filter { wanted.contains($0.id) }
    }

    public var bounds: BoundingBox {
        parts.reduce(BoundingBox.empty) { $0.union($1.geometry.bounds) }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> LibraDocument {
        let document = try JSONDecoder().decode(LibraDocument.self, from: data)
        guard document.formatVersion <= currentFormatVersion else {
            throw FormatError.newerVersion(document.formatVersion)
        }
        return document
    }

    public enum FormatError: LocalizedError {
        case newerVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .newerVersion(let version):
                "This file was saved by a newer version of Libra (format \(version))."
            }
        }
    }
}

/// A named group of parts that moves as one rigid body (a robot link), with its own frame.
public struct PartGroup: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var partIDs: [UUID]
    public var frame: Frame
    /// Draw `frame` in the viewer even when the group isn't selected.
    public var showsFrame: Bool

    public init(id: UUID = UUID(), name: String, partIDs: [UUID], frame: Frame, showsFrame: Bool = false) {
        self.id = id
        self.name = name
        self.partIDs = partIDs
        self.frame = frame
        self.showsFrame = showsFrame
    }
}
