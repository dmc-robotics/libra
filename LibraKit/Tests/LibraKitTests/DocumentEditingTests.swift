import Foundation
@testable import LibraKit
import Testing
import simd

@Suite struct DocumentEditingTests {
    /// Three 0.1 m cubes in a row along X.
    static func makeDocument() -> LibraDocument {
        LibraDocument(parts: (0..<3).map { index in
            Fixtures.boxPart(name: "Cube \(index)", size: [0.1, 0.1, 0.1], corner: [Double(index), 0, 0])
        })
    }

    @Test func createBodyKeepsDocumentOrderAndNames() throws {
        var document = Self.makeDocument()
        let ids = document.parts.map(\.id)
        let createdFirst = document.createBody(partIDs: [ids[2], ids[0]])
        let first = try #require(createdFirst)
        #expect(document.body(first)?.partIDs == [ids[0], ids[2]])
        #expect(document.body(first)?.name == "Body 1")
        #expect(document.body(first)?.frame == document.libraFrame)
        #expect(document.createBody(partIDs: [UUID()]) == nil)
        #expect(document.bodies.count == 1)
    }

    @Test func aPartBelongsToAtMostOneBody() throws {
        var document = Self.makeDocument()
        let ids = document.parts.map(\.id)
        let createdFirst = document.createBody(partIDs: ids)
        let first = try #require(createdFirst)
        let createdSecond = document.createBody(partIDs: [ids[1]])
        let second = try #require(createdSecond)
        #expect(document.body(first)?.partIDs == [ids[0], ids[2]])
        #expect(document.body(second)?.partIDs == [ids[1]])

        document.addParts([ids[0]], toBody: second)
        #expect(document.body(first)?.partIDs == [ids[2]])
        #expect(document.body(second)?.partIDs == [ids[0], ids[1]])
        #expect(document.body(containing: ids[0])?.id == second)

        document.removeFromBodies([ids[0]])
        #expect(document.body(containing: ids[0]) == nil)
    }

    @Test func bodyNamesSkipNamesInUse() throws {
        var document = Self.makeDocument()
        let ids = document.parts.map(\.id)
        let createdFirst = document.createBody(partIDs: [ids[0]])
        let first = try #require(createdFirst)
        document.createBody(partIDs: [ids[1]])
        document.deleteBody(first)
        let createdThird = document.createBody(partIDs: [ids[2]])
        let third = try #require(createdThird)
        #expect(document.body(third)?.name == "Body 3")
    }

    @Test func framesByTarget() throws {
        var document = Self.makeDocument()
        let ids = document.parts.map(\.id)
        let moved = Frame.file.moved(to: [1, 2, 3])

        document.setFrame(moved, for: .libra)
        #expect(document.frame(for: .libra) == moved)

        let createdBody = document.createBody(partIDs: ids)
        let body = try #require(createdBody)
        document.setFrame(Frame.file.rotatedQuarterTurn(about: .z), for: .body(body))
        #expect(document.frame(for: .body(body))?.xAxis == [0, 1, 0])

        // A part has an override frame only while it has an override
        #expect(document.frame(for: .override(ids[0])) == nil)
        document.setFrame(moved, for: .override(ids[0]))
        #expect(document.frame(for: .override(ids[0])) == nil)
        document.changeMassKind(of: ids[0], to: .override)
        document.setFrame(.file, for: .override(ids[0]))
        #expect(document.frame(for: .override(ids[0])) == .file)
    }

    @Test func changingMassKindCarriesValuesOver() throws {
        var document = Self.makeDocument()
        let id = document.parts[0].id
        document.libraFrame = Frame.file.moved(to: [0, 1, 0])
        document.setMass(.measured(2), forParts: [id])
        let measured = try #require(document.part(id)?.massProperties)

        // Measured → override keeps the same physics, entered in the Libra frame
        document.changeMassKind(of: id, to: .override)
        guard case .override(let values) = document.part(id)?.mass else {
            Issue.record("expected an override")
            return
        }
        #expect(values.frame == document.libraFrame)
        expectClose(values.centerOfMass, measured.centerOfMass - [0, 1, 0])
        let overridden = try #require(document.part(id)?.massProperties)
        expectClose(overridden.mass, measured.mass)
        expectClose(overridden.centerOfMass, measured.centerOfMass)
        expectClose(overridden.inertia, measured.inertia)

        // Override → measured keeps the mass
        document.changeMassKind(of: id, to: .measured)
        #expect(document.part(id)?.mass == .measured(2))

        document.changeMassKind(of: id, to: .unassigned)
        #expect(document.part(id)?.mass == .unassigned)
    }

    @Test func setMassForSeveralParts() {
        var document = Self.makeDocument()
        let ids = Set(document.parts.prefix(2).map(\.id))
        document.setMass(.measured(0.5), forParts: ids)
        #expect(document.parts.map(\.mass.kind) == [.measured, .measured, .unassigned])
    }

    @Test func summaryWithoutMassStaysZeroInAnyFrame() {
        let summary = MassSummary(parts: Self.makeDocument().parts)
        let expressed = summary.expressed(in: Frame.file.moved(to: [5, 5, 5]))
        #expect(expressed.properties == .zero)
        #expect(expressed.unassignedCount == 3)
    }
}
