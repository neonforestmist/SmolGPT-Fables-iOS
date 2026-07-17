import CoreML
import CryptoKit
import Foundation

enum ModelInstallError: LocalizedError {
    case badResponse(Int)
    case missingPackageFile(String)
    case checksumMismatch
    case incompatibleManifest(String)
    case unsealedRevision

    var errorDescription: String? {
        switch self {
        case .badResponse(let status): "Hugging Face returned HTTP \(status). The Core ML artifact may not be uploaded yet."
        case .missingPackageFile(let path): "The published checksum list is missing \(path)."
        case .checksumMismatch: "The model download did not match its published SHA-256 checksum."
        case .incompatibleManifest(let detail): "The model manifest is incompatible: \(detail)"
        case .unsealedRevision: "The app is waiting for the immutable Hugging Face commit containing the Core ML model."
        }
    }
}

enum ModelInstallProgress: Sendable {
    case downloading(completedBytes: Int64, totalBytes: Int64)
    case compiling
}

@MainActor
final class ModelInstaller: NSObject, URLSessionDownloadDelegate {
    typealias ProgressHandler = @MainActor (ModelInstallProgress) -> Void

    private var continuation: CheckedContinuation<URL, Error>?
    private var progressHandler: ProgressHandler?
    private var finishedLocation: URL?

    func install(
        progress: @escaping ProgressHandler
    ) async throws -> URL {
        guard ModelArtifact.artifactRevision != "COREML_HUB_REVISION_TO_BE_SET_AFTER_UPLOAD" else {
            throw ModelInstallError.unsealedRevision
        }
        try ModelArtifact.prepareVisibleStorage()
        let checksums = try await fetchChecksums()
        let (manifest, manifestData) = try await fetchManifest()
        guard let manifestChecksum = checksums[ModelArtifact.manifestPath],
              sha256(manifestData) == manifestChecksum.lowercased() else {
            throw ModelInstallError.checksumMismatch
        }
        try validate(manifest)
        let packagePrefix = ModelArtifact.packageDirectory + "/"
        let packagePaths = checksums.keys.filter { $0.hasPrefix(packagePrefix) }.sorted()
        guard packagePaths.contains(where: { $0.hasSuffix("Manifest.json") }) else {
            throw ModelInstallError.missingPackageFile("Manifest.json")
        }
        guard packagePaths.contains(where: { $0.hasSuffix("model.mlmodel") }) else {
            throw ModelInstallError.missingPackageFile("model.mlmodel")
        }
        guard packagePaths.contains(where: { $0.hasSuffix("weights/weight.bin") }) else {
            throw ModelInstallError.missingPackageFile("weights/weight.bin")
        }
        for path in ModelArtifact.tokenizerPaths where checksums[path] == nil {
            throw ModelInstallError.missingPackageFile(path)
        }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmolGPT-CoreML-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let requiredPaths = packagePaths + ModelArtifact.tokenizerPaths
        let publishedFiles = (manifest.packageFiles ?? []) + (manifest.tokenizerFiles ?? [])
        let publishedSizes = Dictionary(
            uniqueKeysWithValues: publishedFiles.map { ($0.path, $0.bytes) }
        )
        for path in requiredPaths where publishedSizes[path] == nil {
            throw ModelInstallError.incompatibleManifest("missing byte size for \(path)")
        }
        let totalBytes = requiredPaths.reduce(Int64(0)) { $0 + (publishedSizes[$1] ?? 0) }
        guard totalBytes > 0 else {
            throw ModelInstallError.incompatibleManifest("download size is unavailable")
        }

        var completedBytes: Int64 = 0
        progress(.downloading(completedBytes: 0, totalBytes: totalBytes))
        for path in requiredPaths {
            let publishedBytes = publishedSizes[path] ?? 0
            let completedBeforeFile = completedBytes
            let temporary = try await download(ModelArtifact.resolveURL(path: path)) { written, expected in
                let expectedForFile = publishedBytes > 0 ? publishedBytes : expected
                let currentFileBytes = min(max(written, 0), max(expectedForFile, 0))
                progress(.downloading(
                    completedBytes: min(completedBeforeFile + currentFileBytes, totalBytes),
                    totalBytes: totalBytes
                ))
            }
            guard try sha256(temporary) == checksums[path]?.lowercased() else {
                try? FileManager.default.removeItem(at: temporary)
                throw ModelInstallError.checksumMismatch
            }
            let destination = work.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: temporary, to: destination)
            completedBytes += publishedBytes
            progress(.downloading(
                completedBytes: min(completedBytes, totalBytes),
                totalBytes: totalBytes
            ))
        }

        let package = work.appendingPathComponent(ModelArtifact.packageDirectory, isDirectory: true)
        progress(.compiling)
        let compiled = try await MLModel.compileModel(at: package)
        let destination = ModelArtifact.modelsDirectory
            .appendingPathComponent(ModelArtifact.compiledModelName, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: compiled, to: destination)

        let tokenizerDestination = ModelArtifact.cachedTokenizerDirectory
        if FileManager.default.fileExists(atPath: tokenizerDestination.path) {
            try FileManager.default.removeItem(at: tokenizerDestination)
        }
        try FileManager.default.createDirectory(at: tokenizerDestination, withIntermediateDirectories: true)
        for path in ModelArtifact.tokenizerPaths {
            try FileManager.default.copyItem(
                at: work.appendingPathComponent(path),
                to: tokenizerDestination.appendingPathComponent(path)
            )
        }
        return destination
    }

    private func fetchManifest() async throws -> (CoreMLArtifactManifest, Data) {
        let url = ModelArtifact.resolveURL(path: ModelArtifact.manifestPath)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ModelInstallError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return (try JSONDecoder().decode(CoreMLArtifactManifest.self, from: data), data)
    }

    private func fetchChecksums() async throws -> [String: String] {
        let url = ModelArtifact.resolveURL(path: ModelArtifact.checksumsPath)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ModelInstallError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let text = String(decoding: data, as: UTF8.self)
        let pairs: [(String, String)] = text.split(whereSeparator: { $0.isNewline }).compactMap { line in
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard parts.count == 2 else { return nil }
            let path = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " *"))
            return (path, String(parts[0]))
        }
        return Dictionary(uniqueKeysWithValues: pairs)
    }

    private func validate(_ manifest: CoreMLArtifactManifest) throws {
        if let source = manifest.sourceModelRevision, source != ModelArtifact.sourceModelRevision {
            throw ModelInstallError.incompatibleManifest("wrong source model revision")
        }
        if let vocabulary = manifest.vocabularySize, vocabulary != 49_152 {
            throw ModelInstallError.incompatibleManifest("expected vocabulary size 49,152")
        }
    }

    private func download(
        _ url: URL,
        progress: @escaping @MainActor (Int64, Int64) -> Void
    ) async throws -> URL {
        self.progressHandler = { event in
            if case let .downloading(completedBytes, totalBytes) = event {
                progress(completedBytes, totalBytes)
            }
        }
        self.finishedLocation = nil
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForResource = 60 * 60
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            progressHandler?(.downloading(
                completedBytes: totalBytesWritten,
                totalBytes: max(totalBytesExpectedToWrite, 0)
            ))
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The delegate's temporary file disappears after this callback, so preserve it first.
        let preserved = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmolGPT-\(UUID().uuidString).download")
        do {
            try FileManager.default.copyItem(at: location, to: preserved)
            Task { @MainActor in
                self.finishedLocation = preserved
                guard let response = downloadTask.response as? HTTPURLResponse else {
                    self.resume(throwing: ModelInstallError.badResponse(-1)); return
                }
                guard (200..<300).contains(response.statusCode) else {
                    self.resume(throwing: ModelInstallError.badResponse(response.statusCode)); return
                }
                self.resume(returning: preserved)
            }
        } catch {
            Task { @MainActor in self.resume(throwing: error) }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        Task { @MainActor in
            if let error { self.resume(throwing: error) }
        }
    }

    private func resume(returning url: URL) {
        let value = continuation
        continuation = nil
        finishedLocation = nil
        value?.resume(returning: url)
    }

    private func resume(throwing error: Error) {
        let value = continuation
        continuation = nil
        finishedLocation = nil
        value?.resume(throwing: error)
    }

    private func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = try? handle.read(upToCount: 4 * 1024 * 1024)
            guard let data, !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
