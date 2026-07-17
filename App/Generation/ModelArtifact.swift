import Foundation

enum ModelArtifact {
    static let repository = "neonforestmist/smolgpt-fables"
    static let sourceModelRevision = "4245b8a4359e4490be58aaf8ac919dc371b6570e"
    static let resourceName = "SmolGPTFablesInt4"
    static let compiledModelName = "SmolGPT-Fables-v1-INT4.mlmodelc"
    static let maxContextTokens = 2_048
    static let vocabularySize = 49_152

    // Immutable Hub commit containing the verified Core ML package.
    static let artifactRevision = "c73cc4d33313159be257b1f6fdaf4fca8fc42c1e"

    static let packageDirectory = "coreml/SmolGPT-Fables-v1-CoreML-INT4.mlpackage"

    static let manifestPath = "coreml/coreml_manifest.json"
    static let checksumsPath = "coreml/coreml-checksums.sha256"
    static let tokenizerPaths = [
        "tokenizer.json", "tokenizer_config.json", "special_tokens_map.json",
        "merges.txt", "vocab.json", "generation_config.json"
    ]

    static func resolveURL(path: String) -> URL {
        let encodedPath = path.split(separator: "/").map(String.init)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)! }
            .joined(separator: "/")
        return URL(string: "https://huggingface.co/\(repository)/resolve/\(artifactRevision)/\(encodedPath)?download=true")!
    }

    static var cachedTokenizerDirectory: URL {
        documentsDirectory.appendingPathComponent("Tokenizer", isDirectory: true)
    }

    static var modelsDirectory: URL {
        documentsDirectory.appendingPathComponent("Models", isDirectory: true)
    }

    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var cachedCompiledURL: URL? {
        migrateLegacyStorageIfNeeded()
        let url = modelsDirectory.appendingPathComponent(compiledModelName, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func prepareVisibleStorage() throws {
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cachedTokenizerDirectory, withIntermediateDirectories: true)

        let readme = documentsDirectory.appendingPathComponent("About SmolGPT-Fables Models.txt")
        if !FileManager.default.fileExists(atPath: readme.path) {
            let contents = """
            SmolGPT-Fables stores its installed Core ML model in the Models folder.
            Tokenizer files are kept in the Tokenizer folder.

            These files are downloaded from:
            https://huggingface.co/neonforestmist/smolgpt-fables
            """
            try contents.write(to: readme, atomically: true, encoding: .utf8)
        }
    }

    private static func migrateLegacyStorageIfNeeded() {
        let fileManager = FileManager.default
        let legacyBase = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SmolGPT-Fables/Models", isDirectory: true)
        let legacyModel = legacyBase.appendingPathComponent("\(resourceName).mlmodelc", isDirectory: true)
        let visibleModel = modelsDirectory.appendingPathComponent(compiledModelName, isDirectory: true)
        let legacyTokenizer = legacyBase.appendingPathComponent("Tokenizer", isDirectory: true)

        try? prepareVisibleStorage()
        if !fileManager.fileExists(atPath: visibleModel.path),
           fileManager.fileExists(atPath: legacyModel.path) {
            try? fileManager.moveItem(at: legacyModel, to: visibleModel)
        }
        if let contents = try? fileManager.contentsOfDirectory(
            at: legacyTokenizer,
            includingPropertiesForKeys: nil
        ) {
            for file in contents {
                let destination = cachedTokenizerDirectory.appendingPathComponent(file.lastPathComponent)
                if !fileManager.fileExists(atPath: destination.path) {
                    try? fileManager.copyItem(at: file, to: destination)
                }
            }
        }
    }
}

struct CoreMLArtifactManifest: Decodable {
    struct FileRecord: Decodable {
        let path: String
        let bytes: Int64
    }

    let sha256: String?
    let bytes: Int64?
    let sourceModelRevision: String?
    let vocabularySize: Int?
    let packageFiles: [FileRecord]?
    let tokenizerFiles: [FileRecord]?

    enum CodingKeys: String, CodingKey {
        case sha256, bytes
        case sourceModelRevision = "source_model_revision"
        case vocabularySize = "vocabulary_size"
        case packageFiles = "package_files"
        case tokenizerFiles = "tokenizer_files"
    }
}
