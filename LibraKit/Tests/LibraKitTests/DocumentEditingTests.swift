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

    @Test func createGroupKeepsDocumentOrderAndNames() throws {
        var document = Self.makeDocument()
        let ids = document.parts.map(\.id)
        let createdFirst = document.createGroup(partIDs: [ids[2], ids[0]])
        let first = try #require(createdFirst)
        #expect(document.group(first)?.partIDs == [ids[0], ids[2]])
        #expect(document.group(first)?.name == "Group 1")
        #expect(document.group(first)?.frame == document.libraFrame)
        #expect(document.createGroup(partIDs: [UUID()]) == nil)
        #expect(document.groups.count == 1)
    }

    @Test func aPartBelongsToAtMostOneGroup() throws {
        var document = Self.makeDocument()
        let ids = document.parts.map(\.id)
        let createdFirst = document.createGroup(partIDs: ids)
        let first = try #require(createdFirst)
        let createdSecond = document.createGroup(partIDs: [ids[1]])
        let second = try #require(createdSecond)
        #expect(document.group(first)?.partIDs == [ids[0], ids[2]])
        #expect(document.group(second)?.partIDs == [ids[1]])

        document.addParts([ids[0]], toGroup: second)
        #expect(document.group(first)?.partIDs == [ids[2]])
        #expect(document.group(second)?.partIDs == [ids[0], ids[1]])
        #expect(document.group(containing: ids[0])?.id == second)

        document.removeFromGroups([ids[0]])
        #expect(document.group(containing: ids[0]) == nil)
    }

    @Test func groupNamesSkipNamesInUse() throws {
        var document = Self.makeDocument()
        let ids = document.parts.map(\.id)
        let createdFirst = document.createGroup(partIDs: [ids[0]])
        let first = try #require(createdFirst)
        document.createGroup(partIDs: [ids[1]])
        document.deleteGroup(first)
        let createdThird = document.createGroup(partIDs: [ids[2]])
        let third = try #require(createdThird)
        #expect(document.group(third)?.name == "Group 3")
    }

    @Test func framesByTarget() throws {
        var document = Self.makeDocument()
        let ids = document.parts.map(\.id)
        let moved = Frame.file.moved(to: [1, 2, 3])

        document.setFrame(moved, for: .libra)
        #expect(document.frame(for: .libra) == moved)

        let createdGroup = document.createGroup(partIDs: ids)
        let group = try #require(createdGroup)
        document.setFrame(Frame.file.rotatedQuarterTurn(about: .z), for: .group(group))
        #expect(document.frame(for: .group(group))?.xAxis == [0, 1, 0])
    }

    @Test func frameVisibility() throws {
        var document = Self.makeDocument()
        let ids = document.parts.map(\.id)
        let createdGroup = document.createGroup(partIDs: [ids[0]])
        let group = try #require(createdGroup)
        #expect(document.shownFrameTargets == [.libra])

        document.setShowsFrame(true, for: .group(group))
        #expect(document.showsFrame(.group(group)))
        #expect(document.shownFrameTargets == [.libra, .group(group)])

        // The Libra frame always shows
        document.setShowsFrame(false, for: .libra)
        #expect(document.showsFrame(.libra))
    }

    @Test func instancesShareAComponent() {
        var document = Self.makeDocument()
        document.parts[0].definitionName = "Wheel"
        document.parts[2].definitionName = "Wheel"
        let ids = document.parts.map(\.id)
        #expect(document.instances(sharingComponentWith: [ids[0]]).map(\.id) == [ids[0], ids[2]])
        #expect(document.instances(sharingComponentWith: [ids[1]]).map(\.id) == [ids[1]])
        #expect(document.instances(sharingComponentWith: [UUID()]).isEmpty)
    }

    @Test func hidingParts() {
        var document = Self.makeDocument()
        let ids = document.parts.map(\.id)
        #expect(!document.areAllHidden([ids[0], ids[1]]))

        document.setHidden(true, forParts: [ids[0]])
        #expect(document.parts.map(\.isHidden) == [true, false, false])
        #expect(!document.areAllHidden([ids[0], ids[1]]))
        document.setHidden(true, forParts: [ids[1]])
        #expect(document.areAllHidden([ids[0], ids[1]]))

        // Nothing to show, so an empty group or assembly isn't hidden
        #expect(!document.areAllHidden([]))
    }

    @Test func setMassForSeveralParts() {
        var document = Self.makeDocument()
        let ids = Set(document.parts.prefix(2).map(\.id))
        document.setMass(0.5, forParts: ids)
        #expect(document.parts.map(\.mass) == [0.5, 0.5, 0])
    }

    @Test func summaryWithoutMassStaysZeroInAnyFrame() {
        let summary = MassSummary(parts: Self.makeDocument().parts)
        let expressed = summary.expressed(in: Frame.file.moved(to: [5, 5, 5]))
        #expect(expressed.properties == .zero)
        #expect(expressed.unassignedCount == 3)
    }
}
