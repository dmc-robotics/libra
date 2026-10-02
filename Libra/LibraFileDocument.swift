import LibraKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let libraDocument = UTType(exportedAs: "com.libra.document")
    static let stepFiles: [UTType] = ["step", "stp"].compactMap { UTType(filenameExtension: $0) }
}

struct LibraFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.libraDocument]

    var content: LibraDocument

    init(content: LibraDocument = LibraDocument()) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        content = try LibraDocument.decoded(from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try content.encoded())
    }
}
