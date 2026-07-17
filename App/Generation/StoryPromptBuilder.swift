import Foundation

enum StoryPromptBuilder {
    static let systemPrompt = """
    You are SmolGPT-Fables. Write a vivid, complete fable from the user's canvas. \
    Output only the finished story continuation. Begin with `### Scene 01:` and \
    emit exactly the requested consecutive, zero-padded scene sections. A scene \
    heading may include a short title after the colon. Use no other Markdown \
    heading. Copy every required name, setting, and unusual detail verbatim. Make \
    each character's described role, personality, and desire affect what they do. \
    Write concrete action and dialogue instead of summarizing instructions. Keep \
    each scene concise, make every scene change the situation, and resolve the \
    ending target inside the final scene. Stop immediately after the final sentence; \
    never add notes, analysis, a moral label, an ending section, or quoted canvas \
    text. /no_think
    """

    static func prompt(for draft: StoryDraft) -> String {
        let title = clean(draft.title).isEmpty ? "A SmolGPT Fable" : clean(draft.title)
        let setting = clean(draft.setting).isEmpty
            ? "A vivid setting that fits the story idea."
            : clean(draft.setting)
        let ending = clean(draft.ending).isEmpty
            ? "Resolve the central conflict and end with a clear emotional change."
            : clean(draft.ending)
        let details = clean(draft.details).isEmpty
            ? "Keep the conflict specific and resolve it on-page."
            : clean(draft.details)
        let moments = clean(draft.importantMoments).isEmpty
            ? defaultBeats(sceneCount: draft.sceneCount)
            : numberedLines(draft.importantMoments)
        let slug = slugify(title)

        let document = """
        # Story: \(title)

        ## Metadata

        - ID: \(slug)-story
        - Story ID: \(slug)
        - Kind: story
        - Status: final
        - Rights: owned
        - Language: en
        - Scene Count: \(draft.sceneCount)
        - Tags: \(slugify(draft.genre)), \(slugify(draft.pointOfView)), \(slugify(draft.structure))

        ## Canvas

        ### Premise

        \(clean(draft.storyIdea))

        ### Setting

        \(setting)

        ### Characters

        \(characters(draft))

        ### Constraints

        - Target scenes: \(draft.sceneCount)
        - Aim for 55 to 100 words in each scene.
        - Keep every supplied name and character detail consistent.
        - \(details)

        ### Beats

        \(moments)

        ### Open Threads

        - [ ] Resolve the central dramatic question.

        ### Ending Target

        \(ending)

        \(outputContract(sceneCount: draft.sceneCount))
        ## Story

        """
        return document.trimmingCharacters(in: .newlines) + "\n\n"
    }

    static func outputContract(sceneCount: Int) -> String {
        let count = min(max(sceneCount, 1), 6)
        let headings = (1...count)
            .map { "`### Scene \(String(format: "%02d", $0)):`" }
            .joined(separator: ", ")
        return """
        Output contract (follow exactly):
        - Use these scene prefixes in order: \(headings).
        - Write exactly \(count) scenes and 45-115 words per scene.
        - Use no heading except those scene headings.
        - Copy every supplied name and required detail verbatim into the story.
        - Show the character-role details through decisions, action, or dialogue.
        - Resolve the ending target in Scene \(String(format: "%02d", count)) and stop.

        """
    }

    private static func characters(_ draft: StoryDraft) -> String {
        [draft.firstCharacter, draft.secondCharacter]
            .filter { !$0.isEmpty }
            .map { character in
                let about = clean(character.about).isEmpty
                    ? "an original character shaped by the story idea"
                    : clean(character.about)
                return "#### \(clean(character.name))\n- Role: \(about)"
            }
            .joined(separator: "\n\n")
    }

    private static func defaultBeats(sceneCount: Int) -> String {
        (1...sceneCount).map { index in
            switch index {
            case 1: "1. Establish the characters, setting, and central problem."
            case sceneCount: "\(index). Complete the central action and show its emotional result."
            default: "\(index). A choice or setback changes what the characters must do next."
            }
        }.joined(separator: "\n")
    }

    private static func numberedLines(_ value: String) -> String {
        value.split(whereSeparator: { $0.isNewline })
            .map(String.init)
            .map { clean($0).replacingOccurrences(of: #"^[-*\d.]+\s*"#, with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func slugify(_ value: String) -> String {
        let parts = value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        let slug = parts.filter { !$0.isEmpty }.joined(separator: "-")
        return slug.isEmpty ? "smolgpt-fable" : String(slug.prefix(64))
    }
}
