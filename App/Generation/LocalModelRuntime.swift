import CoreML
import Foundation
import Tokenizers

enum LocalModelError: LocalizedError {
    case missingModel(String)
    case missingTokenizer
    case incompatibleTokenizer
    case incompatibleModel
    case missingLogits
    case emptyLogits
    case promptTooLong(Int, Int)
    case invalidLogits(Int)

    var errorDescription: String? {
        switch self {
        case .missingModel(let name):
            "\(name) is not installed on this iPhone yet. Download it once from the model repository."
        case .missingTokenizer:
            "The local tokenizer cache is missing. Download the INT4 model to install it."
        case .incompatibleTokenizer:
            "The installed tokenizer is missing the SmolGPT-Fables chat template. Download the model again."
        case .incompatibleModel:
            "The installed model does not expose the SmolGPT-Fables input, mask, logits, and state contract."
        case .missingLogits:
            "The Core ML model completed a prediction without returning logits."
        case .emptyLogits:
            "This simulator's Core ML backend returned empty scores for the INT4 model. Use an iOS 27 simulator or a physical iPhone."
        case .promptTooLong(let count, let maximum):
            "This story setup uses \(count) tokens, but the model supports \(maximum). Shorten a few fields."
        case .invalidLogits(let count):
            "The Core ML model returned \(count) logits; SmolGPT-Fables expects a \(ModelArtifact.vocabularySize)-token vocabulary."
        }
    }
}

@MainActor
final class LocalModelRuntime {
    private(set) var model: MLModel?
    private(set) var tokenizer: (any Tokenizer)?
    private(set) var isLoaded = false

    func load() async throws {
        if isLoaded, model != nil, tokenizer != nil { return }

        let cachedTokenizer = ModelArtifact.cachedTokenizerDirectory
            .appendingPathComponent("tokenizer.json")
        guard FileManager.default.fileExists(atPath: cachedTokenizer.path) else {
            throw LocalModelError.missingTokenizer
        }
        let tokenizerJSON = cachedTokenizer
        let tokenizerFolder = tokenizerJSON.deletingLastPathComponent()
        let localTokenizer = try await AutoTokenizer.from(modelFolder: tokenizerFolder)

        guard let compiledURL = ModelArtifact.cachedCompiledURL else {
            throw LocalModelError.missingModel(ModelArtifact.resourceName)
        }
        #if targetEnvironment(simulator)
        let computeUnits: MLComputeUnits = .cpuOnly
        #else
        let computeUnits: MLComputeUnits = .all
        #endif
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        #if targetEnvironment(simulator)
        SimulatorExecutionPlanCache.prepare(modelURL: compiledURL)
        #endif
        let localModel: MLModel
        do {
            localModel = try MLModel(contentsOf: compiledURL, configuration: configuration)
        } catch {
            #if targetEnvironment(simulator)
            // A failed simulator compilation can leave a multi-gigabyte partial
            // execution plan. Remove it so the next load can make a clean attempt.
            SimulatorExecutionPlanCache.invalidate()
            #endif
            throw error
        }
        let description = localModel.modelDescription
        guard description.inputDescriptionsByName["inputIds"] != nil,
              description.inputDescriptionsByName["causalMask"] != nil,
              description.outputDescriptionsByName["logits"] != nil,
              description.stateDescriptionsByName["keyCache"] != nil,
              description.stateDescriptionsByName["valueCache"] != nil else {
            throw LocalModelError.incompatibleModel
        }

        model = localModel
        tokenizer = localTokenizer
        isLoaded = true
    }

    func unload() {
        model = nil
        tokenizer = nil
        isLoaded = false
    }

    func generate(
        prompt: String,
        draft: StoryDraft,
        progress: @escaping @MainActor (Int, Int, String) -> Void
    ) async throws -> String {
        guard let model, let tokenizer else {
            throw LocalModelError.missingModel("SmolGPTFablesInt4")
        }

        guard tokenizer.hasChatTemplate else {
            throw LocalModelError.incompatibleTokenizer
        }
        let messages: [Message] = [
            ["role": "system", "content": StoryPromptBuilder.systemPrompt],
            ["role": "user", "content": prompt],
        ]
        let promptTokens = try tokenizer.applyChatTemplate(
            messages: messages,
            chatTemplate: nil,
            addGenerationPrompt: true,
            truncation: false,
            maxLength: nil,
            tools: nil
        )
        let maximum = ModelArtifact.maxContextTokens
        guard promptTokens.count < maximum else {
            throw LocalModelError.promptTooLong(promptTokens.count, maximum)
        }
        let budget = min(draft.maxNewTokens, maximum - promptTokens.count)
        let minimumStoryTokens = min(32, budget)
        var allTokens = promptTokens
        var generated: [Int] = []

        let state = model.makeState()
        var processedTokenCount = 0
        let integrationDiagnostics = ProcessInfo.processInfo.environment["RUN_COREML_INTEGRATION"] == "1"

        for index in 0..<budget {
            try Task.checkCancellation()
            let queryTokens = processedTokenCount == 0 ? promptTokens : [allTokens.last!]
            let queryLength = queryTokens.count
            let endStep = processedTokenCount + queryLength
            let input = try inputIDs(queryTokens)
            let mask = try additiveCausalMask(
                queryLength: queryLength,
                startStep: processedTokenCount,
                endStep: endStep
            )
            let features = try MLDictionaryFeatureProvider(dictionary: [
                "inputIds": input,
                "causalMask": mask,
            ])
            let outputs = try await model.prediction(
                from: features,
                using: state
            )
            guard let tensor = outputs.featureValue(for: "logits")?.multiArrayValue else {
                throw LocalModelError.missingLogits
            }
            processedTokenCount = endStep

            var logits = floatValues(from: tensor)
            guard logits.count == ModelArtifact.vocabularySize else {
                throw LocalModelError.invalidLogits(logits.count)
            }
            guard logits.contains(where: { $0.isFinite && $0 != 0 }) else {
                throw LocalModelError.emptyLogits
            }
            if index < minimumStoryTokens {
                // SmolLM's first three vocabulary entries are control tokens
                // (<|endoftext|>, <|im_start|>, and <|im_end|>). A story should
                // not terminate before it has emitted any visible prose.
                for token in 0...2 {
                    logits[token] = -Float.greatestFiniteMagnitude
                }
            }
            if integrationDiagnostics, index == 0 {
                let leaders = logits.enumerated()
                    .filter { $0.element.isFinite }
                    .sorted { $0.element > $1.element }
                    .prefix(8)
                    .map { "\($0.offset)=\($0.element)" }
                    .joined(separator: ", ")
                print(
                    "Core ML logits shape=\(tensor.shape) type=\(tensor.dataType) "
                        + "eos=\(String(describing: tokenizer.eosTokenId)) top=[\(leaders)]"
                )
            }

            let token = sample(
                logits: logits,
                priorTokens: generated,
                temperature: Float(draft.temperature),
                topK: draft.topK,
                topP: Float(draft.topP),
                repetitionPenalty: Float(draft.repetitionPenalty)
            )
            if integrationDiagnostics { print("Core ML sampled token \(index): \(token)") }
            if token == tokenizer.eosTokenId { break }
            generated.append(token)
            allTokens.append(token)
            let text = tokenizer.decode(tokens: generated, skipSpecialTokens: true)
            progress(index + 1, budget, text)
        }
        return tokenizer.decode(tokens: generated, skipSpecialTokens: true)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inputIDs(_ tokens: [Int]) throws -> MLMultiArray {
        let array = try MLMultiArray(
            shape: [1, NSNumber(value: tokens.count)],
            dataType: .int32
        )
        let values = array.dataPointer.bindMemory(to: Int32.self, capacity: tokens.count)
        for (index, token) in tokens.enumerated() {
            values[index] = Int32(token)
        }
        return array
    }

    private func additiveCausalMask(
        queryLength: Int,
        startStep: Int,
        endStep: Int
    ) throws -> MLMultiArray {
        let count = queryLength * endStep
        let array = try MLMultiArray(
            shape: [1, 1, NSNumber(value: queryLength), NSNumber(value: endStep)],
            dataType: .float16
        )
        let values = array.dataPointer.bindMemory(to: Float16.self, capacity: count)
        let blocked = -Float16.greatestFiniteMagnitude
        var index = 0
        for queryOffset in 0..<queryLength {
            let queryPosition = startStep + queryOffset
            for keyPosition in 0..<endStep {
                values[index] = keyPosition <= queryPosition ? 0 : blocked
                index += 1
            }
        }
        return array
    }

    private func floatValues(from array: MLMultiArray) -> [Float] {
        switch array.dataType {
        case .float16:
            let values = UnsafeBufferPointer(
                start: array.dataPointer.assumingMemoryBound(to: Float16.self),
                count: array.count
            )
            return values.map(Float.init)
        case .float32:
            let values = UnsafeBufferPointer(
                start: array.dataPointer.assumingMemoryBound(to: Float.self),
                count: array.count
            )
            return Array(values)
        case .double:
            let values = UnsafeBufferPointer(
                start: array.dataPointer.assumingMemoryBound(to: Double.self),
                count: array.count
            )
            return values.map(Float.init)
        default:
            return []
        }
    }

    private func sample(
        logits: [Float],
        priorTokens: [Int],
        temperature: Float,
        topK: Int,
        topP: Float,
        repetitionPenalty: Float
    ) -> Int {
        var adjusted = logits
        if repetitionPenalty != 1 {
            for token in Set(priorTokens.suffix(256)) where adjusted.indices.contains(token) {
                adjusted[token] = adjusted[token] < 0
                    ? adjusted[token] * repetitionPenalty
                    : adjusted[token] / repetitionPenalty
            }
        }

        let safeTemperature = max(temperature, 0.01)
        let candidates = adjusted.indices
            .map { ($0, adjusted[$0] / safeTemperature) }
            .sorted { $0.1 > $1.1 }
            .prefix(max(1, min(topK, adjusted.count)))

        guard let maximum = candidates.first?.1 else { return 0 }
        let weighted = candidates.map { ($0.0, exp(Double($0.1 - maximum))) }
        let total = weighted.reduce(0) { $0 + $1.1 }
        var cumulative = 0.0
        var nucleus: [(Int, Double)] = []
        for item in weighted {
            nucleus.append(item)
            cumulative += item.1 / total
            if cumulative >= Double(topP) { break }
        }

        let nucleusTotal = nucleus.reduce(0) { $0 + $1.1 }
        var draw = Double.random(in: 0..<nucleusTotal)
        for (token, weight) in nucleus {
            draw -= weight
            if draw <= 0 { return token }
        }
        return nucleus.last?.0 ?? candidates.first!.0
    }
}
