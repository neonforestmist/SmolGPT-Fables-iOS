import XCTest
@testable import SmolGPTFables

final class StoryMarkdownDocumentTests: XCTestCase {
    func testReaderDocumentHasTitleForEverySupportedSceneCount() throws {
        for sceneCount in 1...6 {
            var draft = StoryDraft()
            draft.sceneCount = sceneCount
            let body = (1...sceneCount)
                .map { "### Scene \(String(format: "%02d", $0)):\n\nScene \($0) prose." }
                .joined(separator: "\n\n")

            let document = try XCTUnwrap(
                StoryMarkdownDocument.make(continuation: body, draft: draft)
            )

            XCTAssertTrue(document.markdown.hasPrefix("# A SmolGPT Fable\n\n"))
            XCTAssertEqual(document.markdown.components(separatedBy: "# A SmolGPT Fable").count - 1, 1)
            for index in 1...sceneCount {
                XCTAssertTrue(document.markdown.contains("### Scene \(String(format: "%02d", index))"))
            }
        }
    }

    func testReaderDocumentUsesRequestedTitleAndRemovesEchoedWrapper() throws {
        var draft = StoryDraft()
        draft.title = "  The Lantern Road  "
        let continuation = """
        # Story: The Lantern Road

        ## Story

        ### Scene 01: Homecoming

        Mara carried the lantern home.
        """

        let document = try XCTUnwrap(
            StoryMarkdownDocument.make(continuation: continuation, draft: draft)
        )

        XCTAssertTrue(document.markdown.hasPrefix("# The Lantern Road\n\n### Scene 01"))
        XCTAssertEqual(document.markdown.components(separatedBy: "# The Lantern Road").count - 1, 1)
        XCTAssertFalse(document.markdown.contains("## Story"))
    }

    func testWhitespaceContinuationProducesNoShareableDocument() {
        XCTAssertNil(
            StoryMarkdownDocument.make(continuation: " \n\t ", draft: StoryDraft())
        )
    }

    func testExportWritesNonemptyMarkdownFileWithExactContents() throws {
        var draft = StoryDraft()
        draft.title = "The Copper Bell"
        let document = try XCTUnwrap(
            StoryMarkdownDocument.make(
                continuation: "### Scene 01: The Market\n\nNia rang the bell.",
                draft: draft
            )
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = try document.writeTemporaryFile(in: directory)

        XCTAssertEqual(file.pathExtension, "md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), document.markdown)
        XCTAssertGreaterThan((try Data(contentsOf: file)).count, 0)
    }
}
