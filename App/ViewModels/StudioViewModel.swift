import Foundation
import SwiftUI

@MainActor
final class StudioViewModel: ObservableObject {
    enum ModelState: Equatable {
        case checking
        case ready
        case missing(String)
        case downloading
        case compiling
        case loadFailed(String)
        case failed(String)
    }

    @Published var draft = StoryDraft()
    @Published var modelState = ModelState.checking
    @Published var advanced = false
    @Published var output = ""
    @Published private(set) var shareDocument: StoryMarkdownDocument?
    @Published var isGenerating = false
    @Published var completedTokens = 0
    @Published var tokenBudget = 0
    @Published var errorMessage: String?
    @Published var downloadedBytes: Int64 = 0
    @Published var expectedDownloadBytes: Int64 = 0

    private let runtime = LocalModelRuntime()
    private let installer = ModelInstaller()
    private var generationTask: Task<Void, Never>?

    var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-test-markdown-share")
    }

    private var isLiveGenerationUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-test-live-generation")
    }

    init() {
        do {
            try ModelArtifact.prepareVisibleStorage()
        } catch {
            modelState = .failed("Could not prepare the Files storage folders: \(error.localizedDescription)")
        }

        #if DEBUG
        if isUITesting {
            draft.title = "The Lantern Road"
            draft.storyIdea = "Mara returns a lost lantern before moonrise."
            draft.sceneCount = 3
            draft.firstCharacter = StoryCharacter(name: "Mara", about: "a careful fox")
            draft.secondCharacter = StoryCharacter(name: "Ilyan", about: "a warmhearted owl")
            let continuation = """
            ### Scene 01: The Lost Light

            Mara found the lantern beside the quiet forest road, its flame flickering weakly. She promised to return it before moonrise and called for Ilyan, whose sharp eyes could find paths hidden beneath the autumn leaves.

            ### Scene 02: The Hidden Path

            Ilyan spotted silver scratches on an old cedar and guided Mara through a narrow passage. Wind pressed against them, but Mara shielded the lantern while Ilyan followed its warm reflection between the trees.

            ### Scene 03: Home Before Moonrise

            They reached the lantern keeper as the moon rose over the hill. Its restored light opened the road home, and Mara and Ilyan returned together beneath a bright trail of fireflies.
            """
            shareDocument = StoryMarkdownDocument.make(continuation: continuation, draft: draft)
            output = shareDocument?.markdown ?? ""
            modelState = .ready
        } else if isLiveGenerationUITesting {
            draft.storyIdea = "A fox returns a lost lantern before the moon sets."
            draft.sceneCount = 1
            draft.firstCharacter = StoryCharacter(
                name: "Mara",
                about: "a careful young fox who keeps her promises"
            )
            draft.setting = "A quiet forest path in early autumn"
            draft.maxNewTokens = 48
            draft.temperature = 0.01
            draft.topK = 1
            draft.topP = 1
        }
        #endif
    }

    var progress: Double {
        tokenBudget == 0 ? 0 : Double(completedTokens) / Double(tokenBudget)
    }

    var downloadProgress: Double? {
        guard expectedDownloadBytes > 0 else { return nil }
        return min(max(Double(downloadedBytes) / Double(expectedDownloadBytes), 0), 1)
    }

    var downloadPercentage: Int {
        Int((downloadProgress ?? 0) * 100)
    }

    var downloadSizeText: String {
        guard expectedDownloadBytes > 0 else { return "Preparing download…" }
        let completed = ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: expectedDownloadBytes, countStyle: .file)
        return "\(completed) of \(total)"
    }

    func prepareSelectedModel() async {
        guard !isGenerating else { return }
        modelState = .checking
        runtime.unload()
        do {
            try await runtime.load()
            modelState = .ready
        } catch let error as LocalModelError {
            modelState = .missing(error.localizedDescription)
        } catch {
            modelState = .loadFailed(error.localizedDescription)
        }
    }

    func downloadSelectedModel() {
        guard !isGenerating else { return }
        downloadedBytes = 0
        expectedDownloadBytes = 0
        modelState = .downloading
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await installer.install { event in
                    switch event {
                    case let .downloading(completedBytes, totalBytes):
                        self.downloadedBytes = completedBytes
                        self.expectedDownloadBytes = totalBytes
                        self.modelState = .downloading
                    case .compiling:
                        self.downloadedBytes = self.expectedDownloadBytes
                        self.modelState = .compiling
                    }
                }
                await prepareSelectedModel()
            } catch {
                modelState = .failed(error.localizedDescription)
            }
        }
    }

    func writeStory() {
        guard draft.canGenerate, modelState == .ready, !isGenerating else { return }
        errorMessage = nil
        output = ""
        shareDocument = nil
        completedTokens = 0
        tokenBudget = draft.maxNewTokens
        isGenerating = true
        let prompt = StoryPromptBuilder.prompt(for: draft)
        let snapshot = draft

        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let story = try await runtime.generate(prompt: prompt, draft: snapshot) { [weak self] done, total, text in
                    guard let self else { return }
                    completedTokens = done
                    tokenBudget = total
                    if let document = StoryMarkdownDocument.make(continuation: text, draft: snapshot) {
                        output = document.markdown
                        shareDocument = document
                    }
                }
                if story.isEmpty { errorMessage = "The model returned an empty story. Try again." }
                else if let document = StoryMarkdownDocument.make(continuation: story, draft: snapshot) {
                    output = document.markdown
                    shareDocument = document
                }
            } catch is CancellationError {
                errorMessage = "Writing stopped. Your partial story is still here."
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
            generationTask = nil
        }
    }

    func stop() {
        generationTask?.cancel()
    }
}
