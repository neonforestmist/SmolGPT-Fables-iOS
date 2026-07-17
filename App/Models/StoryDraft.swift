import Foundation

struct StoryCharacter: Equatable, Sendable {
    var name = ""
    var about = ""

    var isEmpty: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && about.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct StoryDraft: Equatable, Sendable {
    static let genres = [
        "Cozy Fantasy", "Adventure", "Mystery", "Folklore", "Fairy Tale",
        "Science Fiction", "Romance", "Historical", "Comedy", "Magical Realism",
        "Gothic", "Hopeful", "Slice of Life"
    ]

    var storyIdea = ""
    var genre = "Cozy Fantasy"
    var sceneCount = 3
    var firstCharacter = StoryCharacter()
    var secondCharacter = StoryCharacter()
    var setting = ""

    var title = ""
    var pointOfView = "Close third person"
    var structure = "Linear three-act"
    var importantMoments = ""
    var details = ""
    var ending = ""

    var temperature = 0.8
    var topP = 0.9
    var topK = 50
    var repetitionPenalty = 1.08
    var maxNewTokens = 640

    var canGenerate: Bool {
        !storyIdea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !firstCharacter.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
