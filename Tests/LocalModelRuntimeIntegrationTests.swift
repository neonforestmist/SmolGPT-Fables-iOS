import XCTest
@testable import SmolGPTFables

@MainActor
final class LocalModelRuntimeIntegrationTests: XCTestCase {
    func testPreloadedCoreMLGeneratesText() async throws {
        guard ProcessInfo.processInfo.environment["RUN_COREML_INTEGRATION"] == "1" else {
            throw XCTSkip("Set RUN_COREML_INTEGRATION=1 to exercise the installed Core ML model.")
        }
        guard ModelArtifact.cachedCompiledURL != nil else {
            XCTFail("The simulator does not have the preloaded Core ML model.")
            return
        }

        var draft = StoryDraft()
        draft.storyIdea = "A fox returns a lost lantern before the moon sets."
        draft.sceneCount = 1
        draft.firstCharacter = StoryCharacter(
            name: "Mara",
            about: "a careful young fox who keeps her promises"
        )
        draft.setting = "A quiet forest path in early autumn"
        draft.maxNewTokens = 16
        draft.temperature = 0.01
        draft.topK = 1
        draft.topP = 1

        let runtime = LocalModelRuntime()
        try await runtime.load()
        let output = try await runtime.generate(
            prompt: StoryPromptBuilder.prompt(for: draft),
            draft: draft
        ) { _, _, _ in }

        print("Core ML smoke output: \(output)")
        XCTAssertFalse(output.isEmpty, "The model should produce text for a valid fable prompt.")
        XCTAssertNotNil(
            output.range(of: #"(?m)^### Scene 01:"#, options: .regularExpression),
            "The trained model should begin with the requested first scene heading."
        )
        let document = try XCTUnwrap(
            StoryMarkdownDocument.make(continuation: output, draft: draft)
        )
        XCTAssertTrue(document.markdown.hasPrefix("# A SmolGPT Fable\n\n"))
    }
}
