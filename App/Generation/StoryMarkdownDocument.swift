import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct StoryMarkdownDocument: Equatable, Sendable, Transferable {
    let title: String
    let markdown: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: markdownContentType) { document in
            SentTransferredFile(try document.writeTemporaryFile())
        }
    }

    static func make(continuation: String, draft: StoryDraft) -> StoryMarkdownDocument? {
        let body = storyBody(from: continuation)
        guard !body.isEmpty else { return nil }

        let title = title(for: draft)
        return StoryMarkdownDocument(
            title: title,
            markdown: "# \(title)\n\n\(body)\n"
        )
    }

    static func title(for draft: StoryDraft) -> String {
        let requested = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return requested.isEmpty ? "A SmolGPT Fable" : requested
    }

    var fileName: String {
        let words = title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let stem = words.isEmpty ? "smolgpt-fable" : words.joined(separator: "-")
        return "\(String(stem.prefix(64))).md"
    }

    @discardableResult
    func writeTemporaryFile(in directory: URL? = nil) throws -> URL {
        let exportDirectory = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("SmolGPT-Fables-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true
        )
        let url = exportDirectory.appendingPathComponent(fileName)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static var markdownContentType: UTType {
        UTType(filenameExtension: "md") ?? .plainText
    }

    private static func storyBody(from continuation: String) -> String {
        var lines = continuation
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)

        // Older generations can echo the document wrapper. The app owns that
        // wrapper, so remove it before producing the single reader-facing title.
        if let first = lines.first, first.hasPrefix("# ") {
            lines.removeFirst()
            while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                lines.removeFirst()
            }
        }
        if lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "## Story" {
            lines.removeFirst()
        }

        return lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
