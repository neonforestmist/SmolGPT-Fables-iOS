import XCTest
@testable import SmolGPTFables

final class SimulatorExecutionPlanCacheTests: XCTestCase {
    private let bundleIdentifier = "com.neonforestmist.SmolGPTFables"

    func testPrepareRemovesCacheMigratedFromAnotherContainer() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let appCache = root.appendingPathComponent(bundleIdentifier, isDirectory: true)
        let cache = appCache.appendingPathComponent("com.apple.e5rt.e5bundlecache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: cache.appendingPathComponent("plan.bin"))

        let model = URL(fileURLWithPath: "/new-container/Models/Fables.mlmodelc")
        SimulatorExecutionPlanCache.prepare(
            modelURL: model,
            cachesDirectory: root,
            bundleIdentifier: bundleIdentifier
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertEqual(
            try String(
                contentsOf: appCache.appendingPathComponent("SmolGPT-CoreML-model-path.txt"),
                encoding: .utf8
            ),
            model.standardizedFileURL.path
        )
    }

    func testPreparePreservesCacheForSameContainer() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = URL(fileURLWithPath: "/same-container/Models/Fables.mlmodelc")
        SimulatorExecutionPlanCache.prepare(
            modelURL: model,
            cachesDirectory: root,
            bundleIdentifier: bundleIdentifier
        )

        let cache = root
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("com.apple.e5rt.e5bundlecache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let plan = cache.appendingPathComponent("plan.bin")
        try Data("current".utf8).write(to: plan)

        SimulatorExecutionPlanCache.prepare(
            modelURL: model,
            cachesDirectory: root,
            bundleIdentifier: bundleIdentifier
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.path))
    }

    func testInvalidateRemovesPlanAndMarker() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = URL(fileURLWithPath: "/container/Models/Fables.mlmodelc")
        SimulatorExecutionPlanCache.prepare(
            modelURL: model,
            cachesDirectory: root,
            bundleIdentifier: bundleIdentifier
        )
        let appCache = root.appendingPathComponent(bundleIdentifier, isDirectory: true)
        let cache = appCache.appendingPathComponent("com.apple.e5rt.e5bundlecache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        SimulatorExecutionPlanCache.invalidate(
            cachesDirectory: root,
            bundleIdentifier: bundleIdentifier
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: appCache.appendingPathComponent("SmolGPT-CoreML-model-path.txt").path
            )
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
