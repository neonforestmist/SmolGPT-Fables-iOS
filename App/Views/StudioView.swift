import SwiftUI

struct StudioView: View {
    @EnvironmentObject private var studio: StudioViewModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case idea, firstName, firstAbout, secondName, secondAbout, setting }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    masthead
                    modelCard
                    storyCard
                    scenesCard
                    charactersSection
                    settingCard
                    advancedSection
                    actionCard
                    if !studio.output.isEmpty || studio.isGenerating { outputCard }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 48)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.canvas.ignoresSafeArea())
            .navigationTitle("SmolGPT-Fables")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
        .tint(.inkBlue)
    }

    private var masthead: some View {
        Text("Shape a story, then write it privately on this iPhone.")
            .font(.body)
            .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    private var modelCard: some View {
        StudioCard(title: "Model", subtitle: "The focused local Core ML build.") {
            HStack(spacing: 10) {
                Image(systemName: "iphone.and.arrow.forward")
                    .foregroundStyle(Color.inkBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SmolGPT-Fables INT4").font(.body.weight(.semibold))
                    Text("The smaller Core ML build for local generation.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: modelIcon)
                    .foregroundStyle(modelColor)
                    .padding(.top, 2)
                Text(modelMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("model-status")
                Spacer(minLength: 0)
            }
            if case .missing = studio.modelState {
                Button { studio.downloadSelectedModel() } label: {
                    Label("Download from Hugging Face", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else if case .failed = studio.modelState {
                Button("Try download again") { studio.downloadSelectedModel() }
                    .buttonStyle(.bordered)
            } else if case .loadFailed = studio.modelState {
                Button("Try loading again") {
                    Task { await studio.prepareSelectedModel() }
                }
                .buttonStyle(.bordered)
            } else if studio.modelState == .downloading {
                ProgressView(value: studio.downloadProgress ?? 0) {
                    Text("Downloading model…")
                } currentValueLabel: {
                    HStack {
                        Text("\(studio.downloadPercentage)%").monospacedDigit().fontWeight(.semibold)
                        Spacer()
                        Text(studio.downloadSizeText).monospacedDigit()
                    }
                }
                .accessibilityValue("\(studio.downloadPercentage) percent, \(studio.downloadSizeText)")
            } else if studio.modelState == .compiling {
                ProgressView("Compiling for this device…")
            } else if studio.modelState == .ready {
                Label("Files → On My iPhone → SmolGPT-Fables → Models", systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var storyCard: some View {
        StudioCard(title: "Story idea", subtitle: "What should happen?") {
            TextEditor(text: $studio.draft.storyIdea)
                .focused($focusedField, equals: .idea)
                .frame(minHeight: 112)
                .textInputAutocapitalization(.sentences)
                .studioInput()

            VStack(alignment: .leading, spacing: 7) {
                Text("Genre or style").font(.subheadline.weight(.semibold))
                Picker("Genre or style", selection: $studio.draft.genre) {
                    ForEach(StoryDraft.genres, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.input, in: RoundedRectangle(cornerRadius: 13))
            }
        }
    }

    private var scenesCard: some View {
        StudioCard(title: "How many scenes?", subtitle: "Choose from 1 to 6.") {
            HStack(spacing: 12) {
                roundButton("minus") { studio.draft.sceneCount = max(1, studio.draft.sceneCount - 1) }
                    .disabled(studio.draft.sceneCount == 1)
                Text("\(studio.draft.sceneCount)")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 72, minHeight: 44)
                    .background(Color.input, in: RoundedRectangle(cornerRadius: 13))
                roundButton("plus") { studio.draft.sceneCount = min(6, studio.draft.sceneCount + 1) }
                    .disabled(studio.draft.sceneCount == 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var charactersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Main characters").font(.title3.weight(.semibold))
                Text("Each person gets a separate name and description.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            CharacterCard(number: 1, optional: false, character: $studio.draft.firstCharacter,
                          nameFocus: $focusedField, nameField: .firstName, aboutField: .firstAbout)
            CharacterCard(number: 2, optional: true, character: $studio.draft.secondCharacter,
                          nameFocus: $focusedField, nameField: .secondName, aboutField: .secondAbout)
        }
    }

    private var settingCard: some View {
        StudioCard(title: "Where does it happen?", subtitle: "A place the characters can act in.") {
            TextField("A lantern market beneath the cliffs", text: $studio.draft.setting, axis: .vertical)
                .focused($focusedField, equals: .setting)
                .lineLimit(2...4)
                .studioInput()
        }
    }

    private var advancedSection: some View {
        StudioCard(title: "Advanced", subtitle: "Optional choices for story shape and generation.") {
            Toggle("Use advanced settings", isOn: $studio.advanced.animation())
                .font(.body.weight(.semibold))
            if studio.advanced {
                VStack(spacing: 14) {
                    labeledField("Title", placeholder: "Leave blank to choose automatically", text: $studio.draft.title)
                    menu("Point of view", selection: $studio.draft.pointOfView,
                         values: ["Close third person", "First person", "Omniscient"])
                    menu("Story shape", selection: $studio.draft.structure,
                         values: ["Linear three-act", "Quest", "Mystery reveal", "Circular fable"])
                    labeledField("Important moments", placeholder: "One moment per line", text: $studio.draft.importantMoments)
                    labeledField("Details to include", placeholder: "Objects, promises, or constraints", text: $studio.draft.details)
                    labeledField("Ending", placeholder: "How should it feel or resolve?", text: $studio.draft.ending)
                    slider("Creativity", value: $studio.draft.temperature, range: 0.2...1.3, valueText: studio.draft.temperature.formatted(.number.precision(.fractionLength(2))))
                    slider("Focus", value: $studio.draft.topP, range: 0.5...1.0, valueText: studio.draft.topP.formatted(.number.precision(.fractionLength(2))))
                    Stepper("Maximum length · \(studio.draft.maxNewTokens) tokens", value: $studio.draft.maxNewTokens, in: 128...1024, step: 64)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var actionCard: some View {
        VStack(spacing: 12) {
            if studio.isGenerating {
                ProgressView(value: studio.progress) {
                    Text("Writing on this iPhone…")
                } currentValueLabel: {
                    Text("\(studio.completedTokens) of up to \(studio.tokenBudget) tokens")
                }
                Button(role: .destructive) { studio.stop() } label: {
                    Label("Stop writing", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button { studio.writeStory() } label: {
                    Label("Write my story", systemImage: "text.book.closed.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!studio.draft.canGenerate || studio.modelState != .ready)
            }
            if let error = studio.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Color.paper, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.line, lineWidth: 1))
    }

    private var outputCard: some View {
        StudioCard(title: "SmolGPT-Fables Output", subtitle: studio.isGenerating ? "The story appears as it is written." : "Ready to read or share.") {
            if studio.output.isEmpty {
                Text("Waiting for the first words…")
                    .font(.body)
            } else {
                MarkdownStoryView(markdown: studio.output)
                    .accessibilityIdentifier("story-markdown-output")
            }
            if let document = studio.shareDocument, !studio.isGenerating {
                ShareLink(
                    item: document,
                    subject: Text(document.title),
                    preview: SharePreview(document.title)
                ) {
                    Label("Share Markdown", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("share-markdown")
            }
        }
    }

    private var modelIcon: String {
        switch studio.modelState {
        case .checking: "hourglass"
        case .ready: "checkmark.circle.fill"
        case .missing: "shippingbox"
        case .downloading: "arrow.down.circle"
        case .compiling: "gearshape.2"
        case .loadFailed, .failed: "exclamationmark.triangle.fill"
        }
    }

    private var modelColor: Color {
        switch studio.modelState {
        case .ready: .green
        case .loadFailed, .failed: .red
        default: .secondary
        }
    }

    private var modelMessage: String {
        switch studio.modelState {
        case .checking: "Checking the local model cache…"
        case .ready: "Ready. Generation stays on this device."
        case .downloading: "Downloading once from Hugging Face. Afterward, generation is fully local."
        case .compiling: "Core ML is compiling the model for this iPhone…"
        case .missing(let message), .loadFailed(let message), .failed(let message): message
        }
    }

    private func roundButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 44, height: 44) }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
    }

    private func labeledField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            TextField(placeholder, text: text, axis: .vertical).lineLimit(1...4).studioInput()
        }
    }

    private func menu(_ title: String, selection: Binding<String>, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Picker(title, selection: selection) { ForEach(values, id: \.self) { Text($0).tag($0) } }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, valueText: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title).font(.subheadline.weight(.semibold)); Spacer(); Text(valueText).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range)
        }
    }
}

private struct MarkdownStoryView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .heading(level, text):
                    Text(text)
                        .font(headingFont(level: level))
                        .frame(maxWidth: .infinity, alignment: .leading)
                case let .paragraph(text):
                    markdownText(text)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraph: [String] = []

        func flushParagraph() {
            let text = paragraph.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(.paragraph(text)) }
            paragraph.removeAll(keepingCapacity: true)
        }

        for line in markdown.components(separatedBy: .newlines) {
            if let heading = heading(from: line) {
                flushParagraph()
                result.append(heading)
            } else if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                flushParagraph()
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return result
    }

    private func heading(from line: String) -> Block? {
        for level in stride(from: 3, through: 1, by: -1) {
            let prefix = String(repeating: "#", count: level) + " "
            if line.hasPrefix(prefix) {
                return .heading(level: level, text: String(line.dropFirst(prefix.count)))
            }
        }
        return nil
    }

    @ViewBuilder
    private func markdownText(_ value: String) -> some View {
        if let attributed = try? AttributedString(markdown: value) {
            Text(attributed)
        } else {
            Text(value)
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: .title2.weight(.bold)
        case 2: .title3.weight(.semibold)
        default: .headline
        }
    }

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
    }
}

private struct CharacterCard<Focus: Hashable>: View {
    let number: Int
    let optional: Bool
    @Binding var character: StoryCharacter
    var nameFocus: FocusState<Focus?>.Binding
    let nameField: Focus
    let aboutField: Focus

    var body: some View {
        StudioCard(title: "Character \(number)\(optional ? " · optional" : "")", subtitle: optional ? "Leave both fields blank for one character." : "Who leads the story?") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.subheadline.weight(.semibold))
                TextField("Mara", text: $character.name).focused(nameFocus, equals: nameField).studioInput()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("About them").font(.subheadline.weight(.semibold))
                TextField("A careful mapmaker who wants credit for her work", text: $character.about, axis: .vertical)
                    .focused(nameFocus, equals: aboutField).lineLimit(2...5).studioInput()
            }
        }
    }
}

private struct StudioCard<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.semibold))
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.paper, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.line, lineWidth: 1))
    }
}

private extension View {
    func studioInput() -> some View {
        padding(12)
            .background(Color.input, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.line.opacity(0.7), lineWidth: 1))
    }
}

private extension Color {
    static let canvas = Color(red: 0.96, green: 0.97, blue: 0.97)
    static let paper = Color(uiColor: .secondarySystemBackground)
    static let input = Color(uiColor: .systemBackground)
    static let line = Color(red: 0.50, green: 0.58, blue: 0.68)
    static let inkBlue = Color(red: 0.12, green: 0.24, blue: 0.39)
}
