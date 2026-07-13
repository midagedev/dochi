import AgentRuntimeApple
import AgentRuntimeCore
import AgentRuntimeFileMemory
import AgentRuntimeMemory
import Foundation
import XCTest
@testable import Dochi

@MainActor
final class DochiFileMemoryControllerTests: XCTestCase {
    func testLocalMarkdownIsIndexedIntoExactApplicationScope() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("# 취향\n\n사용자는 따뜻한 차를 좋아합니다.".utf8).write(
            to: root.appendingPathComponent("profile.md")
        )
        let store = InMemoryMemoryStore()
        let preferences = DochiFileMemoryPreferencesBox(DochiFileMemoryPreferences(
            memoryEnabled: true,
            fileMemoryEnabled: true,
            location: .local
        ))
        let controller = DochiFileMemoryController(
            appID: "test.dochi",
            store: store,
            localRootURL: root,
            preferencesProvider: { preferences.value }
        )

        await controller.synchronize()

        guard case .synchronized(let location, let files, let chunks, _, _) = controller.status else {
            return XCTFail("Expected a successful local synchronization")
        }
        XCTAssertEqual(location, .local)
        XCTAssertEqual(files, 1)
        XCTAssertGreaterThan(chunks, 0)
        let result = try await store.retrieve(MemoryQuery(
            scopes: [.application(appID: "test.dochi")],
            text: "따뜻한 차"
        ))
        XCTAssertTrue(result.hits.contains { $0.record.content.contains("따뜻한 차") })
        let otherScope = try await store.retrieve(MemoryQuery(
            scopes: [.application(appID: "other.app")],
            text: "따뜻한 차"
        ))
        XCTAssertTrue(otherScope.hits.isEmpty)

        preferences.value.fileMemoryEnabled = false
        await controller.synchronize()
        XCTAssertEqual(controller.status, .disabled)
        let inactive = try await store.retrieve(MemoryQuery(
            scopes: [.application(appID: "test.dochi")],
            text: "따뜻한 차"
        ))
        XCTAssertTrue(inactive.hits.isEmpty)
        let archived = try await store.retrieve(MemoryQuery(
            scopes: [.application(appID: "test.dochi")],
            text: "따뜻한 차",
            statuses: [.archived]
        ))
        XCTAssertFalse(archived.hits.isEmpty)
    }

    func testICloudFailureArchivesLocalIndexAndDoesNotFallBack() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("# 지속 기억\n\n기존 색인은 남아야 합니다.".utf8).write(
            to: root.appendingPathComponent("memory.md")
        )
        let store = InMemoryMemoryStore()
        let preferences = DochiFileMemoryPreferencesBox(DochiFileMemoryPreferences(
            memoryEnabled: true,
            fileMemoryEnabled: true,
            location: .local
        ))
        let probe = DochiFileAccessFactoryProbe()
        let controller = DochiFileMemoryController(
            appID: "test.dochi",
            store: store,
            localRootURL: root,
            preferencesProvider: { preferences.value },
            fileAccessFactory: { location, localRoot in
                probe.record(location)
                switch location {
                case .local:
                    return try LocalDirectoryFileMemoryAccess(rootURL: localRoot)
                case .iCloudDrive:
                    return FailingDochiFileMemoryAccess()
                }
            }
        )
        await controller.synchronize()

        preferences.value.location = .iCloudDrive
        await controller.synchronize()

        XCTAssertEqual(probe.locations, [.local, .iCloudDrive])
        guard case .unavailable(let location, let message) = controller.status else {
            return XCTFail("Expected iCloud to be unavailable")
        }
        XCTAssertEqual(location, .iCloudDrive)
        XCTAssertTrue(message.contains("로컬 색인은 사용하지 않습니다"))
        XCTAssertTrue(controller.allowsMemoryAccess)
        let active = try await store.retrieve(MemoryQuery(
            scopes: [.application(appID: "test.dochi")],
            text: "기존 색인"
        ))
        XCTAssertTrue(active.hits.isEmpty)
        let archived = try await store.retrieve(MemoryQuery(
            scopes: [.application(appID: "test.dochi")],
            text: "기존 색인",
            statuses: [.archived]
        ))
        XCTAssertFalse(archived.hits.isEmpty)
    }

    func testConcurrentSynchronizationsAreCoalesced() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = InMemoryMemoryStore()
        let preferences = DochiFileMemoryPreferencesBox(DochiFileMemoryPreferences(
            memoryEnabled: true,
            fileMemoryEnabled: true,
            location: .local
        ))
        let probe = DochiFileAccessFactoryProbe()
        let gate = DochiFileMemorySynchronizationGate()
        let controller = DochiFileMemoryController(
            appID: "test.dochi",
            store: store,
            localRootURL: root,
            preferencesProvider: { preferences.value },
            fileAccessFactory: { location, _ in
                probe.record(location)
                return BlockingEmptyDochiFileMemoryAccess(gate: gate)
            }
        )

        let startup = Task { @MainActor in await controller.synchronize() }
        await gate.waitUntilScanStarts()
        let manualRefresh = Task { @MainActor in await controller.synchronize() }
        await Task.yield()
        await gate.allowScanToFinish()
        await startup.value
        await manualRefresh.value

        XCTAssertEqual(probe.locations, [.local])
        guard case .synchronized(let location, let files, _, _, _) = controller.status else {
            return XCTFail("Expected a successful coalesced synchronization")
        }
        XCTAssertEqual(location, .local)
        XCTAssertEqual(files, 0)
    }

    func testICloudRefreshFailureRetainsOnlyPriorICloudIndex() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("# iCloud 기억\n\n선택한 위치의 마지막 기억입니다.".utf8).write(
            to: root.appendingPathComponent("icloud.md")
        )
        let store = InMemoryMemoryStore()
        let preferences = DochiFileMemoryPreferencesBox(DochiFileMemoryPreferences(
            memoryEnabled: true,
            fileMemoryEnabled: true,
            location: .iCloudDrive
        ))
        let attempts = DochiICloudAccessAttemptProbe()
        let controller = DochiFileMemoryController(
            appID: "test.dochi",
            store: store,
            localRootURL: root,
            preferencesProvider: { preferences.value },
            fileAccessFactory: { _, localRoot in
                if attempts.takeNext() == 1 {
                    return try LocalDirectoryFileMemoryAccess(rootURL: localRoot)
                }
                return FailingDochiFileMemoryAccess()
            }
        )

        await controller.synchronize()
        await controller.synchronize()

        guard case .unavailable(let location, _) = controller.status else {
            return XCTFail("Expected the second iCloud refresh to fail")
        }
        XCTAssertEqual(location, .iCloudDrive)
        let retained = try await store.retrieve(MemoryQuery(
            scopes: [.application(appID: "test.dochi")],
            text: "마지막 기억"
        ))
        XCTAssertFalse(retained.hits.isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DochiFileMemoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct FailingDochiFileMemoryAccess: FileMemoryFileAccess {
    var rootDescription: String { get async { "iCloud://test" } }

    func listDirectory(
        at path: FileMemoryPath,
        maximumEntryCount: Int
    ) async throws -> [FileMemoryDirectoryEntry] {
        throw ICloudDriveFileMemoryError.iCloudIdentityUnavailable
    }

    func readFile(
        at path: FileMemoryPath,
        maximumByteCount: Int
    ) async throws -> FileMemoryReadResult {
        throw ICloudDriveFileMemoryError.iCloudIdentityUnavailable
    }
}

private struct BlockingEmptyDochiFileMemoryAccess: FileMemoryFileAccess {
    let gate: DochiFileMemorySynchronizationGate

    var rootDescription: String { get async { "memory://blocking-test" } }

    func listDirectory(
        at path: FileMemoryPath,
        maximumEntryCount: Int
    ) async throws -> [FileMemoryDirectoryEntry] {
        await gate.pauseScan()
        return []
    }

    func readFile(
        at path: FileMemoryPath,
        maximumByteCount: Int
    ) async throws -> FileMemoryReadResult {
        throw CocoaError(.fileReadUnknown)
    }
}

private actor DochiFileMemorySynchronizationGate {
    private var scanStarted = false
    private var scanCanFinish = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var finishWaiter: CheckedContinuation<Void, Never>?

    func pauseScan() async {
        scanStarted = true
        startWaiter?.resume()
        startWaiter = nil
        guard !scanCanFinish else { return }
        await withCheckedContinuation { finishWaiter = $0 }
    }

    func waitUntilScanStarts() async {
        guard !scanStarted else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func allowScanToFinish() {
        scanCanFinish = true
        finishWaiter?.resume()
        finishWaiter = nil
    }
}

private final class DochiFileAccessFactoryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedLocations: [DochiFileMemoryLocation] = []

    var locations: [DochiFileMemoryLocation] {
        lock.withLock { storedLocations }
    }

    func record(_ location: DochiFileMemoryLocation) {
        lock.withLock { storedLocations.append(location) }
    }
}

private final class DochiICloudAccessAttemptProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var attempt = 0

    func takeNext() -> Int {
        lock.withLock {
            attempt += 1
            return attempt
        }
    }
}

@MainActor
private final class DochiFileMemoryPreferencesBox {
    var value: DochiFileMemoryPreferences

    init(_ value: DochiFileMemoryPreferences) {
        self.value = value
    }
}
