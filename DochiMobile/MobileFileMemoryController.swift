import AgentRuntimeApple
import AgentRuntimeCore
import AgentRuntimeFileMemory
import AgentRuntimeMemory
import Foundation

enum MobileFileMemoryLocation: String, CaseIterable, Identifiable, Sendable {
    case local
    case iCloudDrive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: "이 iPhone 또는 iPad"
        case .iCloudDrive: "iCloud Drive"
        }
    }
}

struct MobileFileMemoryPreferences: Sendable, Equatable {
    var memoryEnabled: Bool
    var fileMemoryEnabled: Bool
    var location: MobileFileMemoryLocation
}

enum MobileFileMemoryStatus: Sendable, Equatable {
    case disabled
    case waiting(MobileFileMemoryLocation)
    case synchronizing(MobileFileMemoryLocation)
    case synchronized(
        location: MobileFileMemoryLocation,
        files: Int,
        chunks: Int,
        generation: Int,
        at: Date
    )
    case unavailable(location: MobileFileMemoryLocation, message: String)

    var isSynchronizing: Bool {
        if case .synchronizing = self { return true }
        return false
    }

    var displayText: String {
        switch self {
        case .disabled:
            "꺼짐"
        case .waiting(let location):
            location.displayName + "에서 새로고침 대기 중"
        case .synchronizing(let location):
            location.displayName + " 파일 확인 중"
        case .synchronized(let location, let files, let chunks, _, _):
            location.displayName + " · 파일 \(files)개 · 기억 조각 \(chunks)개"
        case .unavailable(let location, let message):
            location.displayName + " 사용 불가 · " + message
        }
    }
}

/// iOS lifecycle wrapper around AgentRuntimeKit's canonical file scanner.
/// A selected iCloud source is never replaced with the device-local source.
@MainActor
@Observable
final class MobileFileMemoryController {
    typealias FileAccessFactory = @Sendable (
        _ location: MobileFileMemoryLocation,
        _ localRootURL: URL
    ) throws -> any FileMemoryFileAccess

    nonisolated static let iCloudContainerIdentifier = "iCloud.com.hckim.dochi"
    nonisolated static let legacySourceID = "dochi.canonical-file-memory.v1"

    private(set) var status: MobileFileMemoryStatus = .disabled
    private(set) var allowsMemoryAccess = true

    private let appID: String
    private let store: any MemorySourceReconciliationStore
    private let localRootURL: URL
    private let preferencesProvider: @MainActor () -> MobileFileMemoryPreferences
    private let fileAccessFactory: FileAccessFactory
    private var activeSynchronization: Task<Void, Never>?

    init(
        appID: String,
        store: any MemorySourceReconciliationStore,
        localRootURL: URL,
        preferencesProvider: @escaping @MainActor () -> MobileFileMemoryPreferences,
        fileAccessFactory: FileAccessFactory? = nil
    ) {
        self.appID = appID
        self.store = store
        self.localRootURL = localRootURL.standardizedFileURL
        self.preferencesProvider = preferencesProvider
        self.fileAccessFactory = fileAccessFactory ?? Self.makeFileAccess
        let preferences = preferencesProvider()
        status = preferences.memoryEnabled && preferences.fileMemoryEnabled
            ? .waiting(preferences.location)
            : .disabled
    }

    func synchronize() async {
        if let activeSynchronization {
            await activeSynchronization.value
            return
        }

        let preferences = preferencesProvider()
        guard preferences.memoryEnabled else {
            status = .disabled
            return
        }

        status = .synchronizing(preferences.location)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            if preferences.fileMemoryEnabled {
                await self.performSynchronization(preferences: preferences)
            } else {
                await self.deactivateSource(preferences: preferences)
            }
        }
        activeSynchronization = task
        await task.value
        activeSynchronization = nil
    }

    private func deactivateSource(preferences: MobileFileMemoryPreferences) async {
        do {
            try await deactivateSources(except: nil)
            allowsMemoryAccess = true
            status = .disabled
        } catch is CancellationError {
            status = .waiting(preferences.location)
        } catch {
            allowsMemoryAccess = false
            status = .unavailable(
                location: preferences.location,
                message: "파일 메모리 색인을 비활성화하지 못했습니다."
            )
        }
    }

    private func performSynchronization(preferences: MobileFileMemoryPreferences) async {
        do {
            let selectedSourceID = Self.sourceID(for: preferences.location)
            try await deactivateSources(except: selectedSourceID)
            allowsMemoryAccess = true
            let fileAccess = try fileAccessFactory(preferences.location, localRootURL)
            let configuration = try FileMemoryConfiguration(
                sourceID: selectedSourceID,
                scope: .application(appID: appID),
                maximumSensitivity: .privateData,
                missingPolicy: .archive,
                memoryKind: .observation
            )
            let report = try await FileMemorySynchronizer(
                configuration: configuration,
                fileAccess: fileAccess,
                store: store
            ).synchronize()
            guard preferencesProvider() == preferences else {
                let latest = preferencesProvider()
                status = latest.memoryEnabled && latest.fileMemoryEnabled
                    ? .waiting(latest.location)
                    : .disabled
                return
            }
            status = .synchronized(
                location: preferences.location,
                files: report.filesScanned,
                chunks: report.chunkCount,
                generation: report.generation,
                at: .now
            )
        } catch is CancellationError {
            guard preferencesProvider() == preferences else { return }
            status = .waiting(preferences.location)
        } catch {
            guard preferencesProvider() == preferences else { return }
            if error is MobileFileMemoryControllerError {
                allowsMemoryAccess = false
            }
            status = .unavailable(
                location: preferences.location,
                message: Self.safeFailureMessage(error, location: preferences.location)
            )
        }
    }

    private func deactivateSources(except selectedSourceID: String?) async throws {
        let sourceIDs = [
            Self.legacySourceID,
            Self.sourceID(for: .local),
            Self.sourceID(for: .iCloudDrive),
        ]
        for sourceID in sourceIDs where sourceID != selectedSourceID {
            do {
                try await archiveAllRecords(sourceID: sourceID)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw MobileFileMemoryControllerError.sourceIsolationFailed
            }
        }
    }

    private func archiveAllRecords(sourceID: String) async throws {
        let scope = MemoryScope.application(appID: appID)
        for attempt in 0...3 {
            try Task.checkCancellation()
            let state = try await store.sourceState(identifier: sourceID, scope: scope)
            guard let state else { return }
            do {
                _ = try await store.reconcileSourceSnapshot(
                    MemorySourceSnapshot(identifier: sourceID, scope: scope, records: []),
                    expectedGeneration: state.generation,
                    missingPolicy: .archive
                )
                return
            } catch let reconciliationError as MemorySourceReconciliationError {
                guard case .generationConflict = reconciliationError,
                      attempt < 3 else {
                    throw reconciliationError
                }
            }
        }
    }

    private nonisolated static func sourceID(
        for location: MobileFileMemoryLocation
    ) -> String {
        switch location {
        case .local: "dochi.canonical-file-memory.local.v1"
        case .iCloudDrive: "dochi.canonical-file-memory.icloud-drive.v1"
        }
    }

    private nonisolated static func makeFileAccess(
        location: MobileFileMemoryLocation,
        localRootURL: URL
    ) throws -> any FileMemoryFileAccess {
        switch location {
        case .local:
            try prepareLocalRoot(localRootURL)
            return try LocalDirectoryFileMemoryAccess(rootURL: localRootURL)
        case .iCloudDrive:
            let configuration = try ICloudDriveFileMemoryAccess.Configuration(
                containerIdentifier: iCloudContainerIdentifier,
                documentsSubdirectory: try FileMemoryPath("Dochi/Memory")
            )
            return ICloudDriveFileMemoryAccess(configuration: configuration)
        }
    }

    private nonisolated static func prepareLocalRoot(_ rootURL: URL) throws {
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
    }

    private nonisolated static func safeFailureMessage(
        _ error: any Error,
        location: MobileFileMemoryLocation
    ) -> String {
        if error is MobileFileMemoryControllerError {
            return "다른 위치의 색인을 안전하게 분리하지 못해 기억 사용을 멈췄습니다."
        }
        if location == .iCloudDrive {
            switch error as? ICloudDriveFileMemoryError {
            case .iCloudIdentityUnavailable?:
                return "iCloud 로그인을 확인해 주세요. 선택한 iCloud 색인만 유지하며 기기 색인은 사용하지 않습니다."
            case .containerUnavailable?:
                return "앱의 iCloud 권한을 확인해 주세요. 기기 색인은 사용하지 않습니다."
            case .unresolvedVersionConflict?:
                return "충돌 파일을 해결한 뒤 다시 시도해 주세요. 기기 색인은 사용하지 않습니다."
            case .downloadTimedOut?, .downloadFailed?:
                return "파일 다운로드가 끝난 뒤 다시 시도해 주세요. 기기 색인은 사용하지 않습니다."
            default:
                return "iCloud 파일을 읽지 못했습니다. 선택한 iCloud 색인만 유지하며 기기 색인은 사용하지 않습니다."
            }
        }
        return "파일을 읽지 못했습니다. 선택한 위치의 마지막 색인만 유지됩니다."
    }
}

private enum MobileFileMemoryControllerError: Error, Sendable {
    case sourceIsolationFailed
}
