import XCTest
@testable import SmolGPTFables

final class StoryPromptBuilderTests: XCTestCase {
    func testPromptKeepsNamesAndSceneCount() {
        var draft = StoryDraft()
        draft.storyIdea = "Two friends repair a broken lighthouse lens."
        draft.sceneCount = 4
        draft.firstCharacter = StoryCharacter(name: "Mina Vale", about: "a patient glassmaker")
        draft.secondCharacter = StoryCharacter(name: "Orin Reed", about: "a nervous keeper")

        let prompt = StoryPromptBuilder.prompt(for: draft)

        XCTAssertTrue(prompt.contains("- Scene Count: 4"))
        XCTAssertTrue(prompt.contains("#### Mina Vale"))
        XCTAssertTrue(prompt.contains("#### Orin Reed"))
        XCTAssertTrue(prompt.hasSuffix("## Story\n\n"))
    }

    func testAdvancedFieldsAppearVerbatim() {
        var draft = StoryDraft()
        draft.storyIdea = "A baker follows a trail of blue feathers."
        draft.firstCharacter = StoryCharacter(name: "Nia", about: "a stubborn baker")
        draft.ending = "Nia gives the last loaf away."
        draft.details = "Include a copper bell."

        let prompt = StoryPromptBuilder.prompt(for: draft)

        XCTAssertTrue(prompt.contains("Nia gives the last loaf away."))
        XCTAssertTrue(prompt.contains("Include a copper bell."))
    }

    func testOutputContractListsEveryRequestedSceneInOrder() {
        for sceneCount in 1...6 {
            let contract = StoryPromptBuilder.outputContract(sceneCount: sceneCount)

            XCTAssertTrue(contract.contains("Write exactly \(sceneCount) scenes"))
            for index in 1...sceneCount {
                XCTAssertTrue(contract.contains("`### Scene \(String(format: "%02d", index)):`"))
            }
            if sceneCount < 6 {
                XCTAssertFalse(contract.contains("`### Scene \(String(format: "%02d", sceneCount + 1)):`"))
            }
        }
    }
}
