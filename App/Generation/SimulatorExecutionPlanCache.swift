import Foundation

enum SimulatorExecutionPlanCache {
    private static let executionPlanDirectoryName = "com.apple.e5rt.e5bundlecache"
    private static let markerFileName = "SmolGPT-CoreML-model-path.txt"
    private static let maximumExpectedCacheBytes: Int64 = 5_000_000_000

    static func prepare(
        modelURL: URL,
        cachesDirectory: URL? = nil,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.neonforestmist.SmolGPTFables"
    ) {
        guard let root = cachesDirectory ?? FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else { return }

        let appCacheRoot = root.appendingPathComponent(bundleIdentifier, isDirectory: true)
        let marker = appCacheRoot.appendingPathComponent(markerFileName)
        let cache = appCacheRoot.appendingPathComponent(executionPlanDirectoryName, isDirectory: true)
        let currentPath = modelURL.standardizedFileURL.path
        let previousPath = try? String(contentsOf: marker, encoding: .utf8)
        let migratedContainer = previousPath != currentPath
        let oversizedCache = allocatedSize(of: cache) > maximumExpectedCacheBytes

        if migratedContainer || oversizedCache {
            try? FileManager.default.removeItem(at: cache)
        }

        try? FileManager.default.createDirectory(at: appCacheRoot, withIntermediateDirectories: true)
        try? currentPath.write(to: marker, atomically: true, encoding: .utf8)
    }

    static func invalidate(
        cachesDirectory: URL? = nil,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.neonforestmist.SmolGPTFables"
    ) {
        guard let root = cachesDirectory ?? FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else { return }
        let appCacheRoot = root.appendingPathComponent(bundleIdentifier, isDirectory: true)
        try? FileManager.default.removeItem(
            at: appCacheRoot.appendingPathComponent(executionPlanDirectoryName, isDirectory: true)
        )
        try? FileManager.default.removeItem(
            at: appCacheRoot.appendingPathComponent(markerFileName)
        )
    }

    private static func allocatedSize(of directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileAllocatedSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [
                .fileAllocatedSizeKey,
                .totalFileAllocatedSizeKey,
            ]) else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            if total > maximumExpectedCacheBytes { break }
        }
        return total
    }
}
