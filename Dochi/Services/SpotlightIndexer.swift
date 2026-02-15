import Foundation
import AppKit
import CoreSpotlight
import UniformTypeIdentifiers

/// CoreSpotlight 인덱싱 서비스 (H-4)
/// 대화와 메모리를 macOS Spotlight에서 검색 가능하도록 인덱싱한다.
@MainActor
@Observable
final class SpotlightIndexer: SpotlightIndexerProtocol {

    // MARK: - Published State

    private(set) var indexedItemCount: Int = 0
    private(set) var isRebuilding: Bool = false
    private(set) var rebuildProgress: Double = 0.0
    private(set) var lastIndexedAt: Date? = nil

    // MARK: - Constants

    static let domainIdentifier = "com.hckim.dochi"
    private static let conversationPrefix = "dochi-conversation-"
    private static let memoryPrefix = "dochi-memory-"
    private static let maxDescriptionLength = 200

    // MARK: - Dependencies

    private let searchableIndex: CSSearchableIndex
    private let settings: AppSettings

    // MARK: - Init

    init(settings: AppSettings, searchableIndex: CSSearchableIndex = .default()) {
        self.settings = settings
        self.searchableIndex = searchableIndex
        Log.app.info("SpotlightIndexer initialized")
    }

    // MARK: - Conversation Indexing

    func indexConversation(_ conversation: Conversation) {
        guard settings.spotlightIndexingEnabled, settings.spotlightIndexConversations else { return }

        let uniqueId = Self.conversationPrefix + conversation.id.uuidString
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = conversation.title
        attributeSet.contentDescription = conversationDescription(conversation)
        attributeSet.domainIdentifier = Self.domainIdentifier
        attributeSet.thumbnailData = appIconData()
        attributeSet.contentURL = URL(string: "dochi://conversation/\(conversation.id.uuidString)")
        attributeSet.contentModificationDate = conversation.updatedAt

        let item = CSSearchableItem(
            uniqueIdentifier: uniqueId,
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attributeSet
        )

        searchableIndex.indexSearchableItems([item]) { [weak self] error in
            Task { @MainActor in
                if let error {
                    Log.app.error("Spotlight: 대화 인덱싱 실패 — \(error.localizedDescription)")
                } else {
                    self?.indexedItemCount += 1
                    self?.lastIndexedAt = Date()
                    Log.app.debug("Spotlight: 대화 인덱싱 완료 — \(conversation.title)")
                }
            }
        }
    }

    func removeConversation(id: UUID) {
        let uniqueId = Self.conversationPrefix + id.uuidString
        searchableIndex.deleteSearchableItems(withIdentifiers: [uniqueId]) { [weak self] error in
            Task { @MainActor in
                if let error {
                    Log.app.error("Spotlight: 대화 인덱스 제거 실패 — \(error.localizedDescription)")
                } else {
                    self?.indexedItemCount = max(0, (self?.indexedItemCount ?? 1) - 1)
                    Log.app.debug("Spotlight: 대화 인덱스 제거 완료 — \(id)")
                }
            }
        }
    }

    // MARK: - Memory Indexing

    func indexMemory(scope: String, identifier: String, title: String, content: String) {
        guard settings.spotlightIndexingEnabled else { return }

        // Check scope-specific settings
        switch scope {
        case "personal":
            guard settings.spotlightIndexPersonalMemory else { return }
        case "agent":
            guard settings.spotlightIndexAgentMemory else { return }
        case "workspace":
            guard settings.spotlightIndexWorkspaceMemory else { return }
        default:
            break
        }

        let uniqueId = Self.memoryPrefix + identifier
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = title
        attributeSet.contentDescription = String(content.prefix(Self.maxDescriptionLength))
        attributeSet.domainIdentifier = Self.domainIdentifier
        attributeSet.thumbnailData = appIconData()
        attributeSet.contentURL = URL(string: "dochi://memory/\(identifier)")
        attributeSet.contentModificationDate = Date()

        let item = CSSearchableItem(
            uniqueIdentifier: uniqueId,
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attributeSet
        )

        searchableIndex.indexSearchableItems([item]) { [weak self] error in
            Task { @MainActor in
                if let error {
                    Log.app.error("Spotlight: 메모리 인덱싱 실패 — \(error.localizedDescription)")
                } else {
                    self?.indexedItemCount += 1
                    self?.lastIndexedAt = Date()
                    Log.app.debug("Spotlight: 메모리 인덱싱 완료 — \(title)")
                }
            }
        }
    }

    func removeMemory(identifier: String) {
        let uniqueId = Self.memoryPrefix + identifier
        searchableIndex.deleteSearchableItems(withIdentifiers: [uniqueId]) { [weak self] error in
            Task { @MainActor in
                if let error {
                    Log.app.error("Spotlight: 메모리 인덱스 제거 실패 — \(error.localizedDescription)")
                } else {
                    self?.indexedItemCount = max(0, (self?.indexedItemCount ?? 1) - 1)
                    Log.app.debug("Spotlight: 메모리 인덱스 제거 완료 — \(identifier)")
                }
            }
        }
    }

    // MARK: - Rebuild / Clear

    func rebuildAllIndices(
        conversations: [Conversation],
        contextService: ContextServiceProtocol,
        sessionContext: SessionContext
    ) async {
        guard settings.spotlightIndexingEnabled else {
            Log.app.info("Spotlight: 인덱싱 비활성화 상태 — 재구축 건너뜀")
            return
        }

        isRebuilding = true
        rebuildProgress = 0.0
        indexedItemCount = 0

        Log.app.info("Spotlight: 전체 인덱스 재구축 시작")

        // Clear existing indices first
        await clearAllIndicesInternal()

        // Calculate total items for progress
        var items: [CSSearchableItem] = []

        // Index conversations
        if settings.spotlightIndexConversations {
            for (index, conversation) in conversations.enumerated() {
                let uniqueId = Self.conversationPrefix + conversation.id.uuidString
                let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
                attributeSet.title = conversation.title
                attributeSet.contentDescription = conversationDescription(conversation)
                attributeSet.domainIdentifier = Self.domainIdentifier
                attributeSet.thumbnailData = appIconData()
                attributeSet.contentURL = URL(string: "dochi://conversation/\(conversation.id.uuidString)")
                attributeSet.contentModificationDate = conversation.updatedAt

                let item = CSSearchableItem(
                    uniqueIdentifier: uniqueId,
                    domainIdentifier: Self.domainIdentifier,
                    attributeSet: attributeSet
                )
                items.append(item)

                // Update progress (conversations take first 60%)
                let conversationProgress = Double(index + 1) / Double(max(conversations.count, 1)) * 0.6
                rebuildProgress = conversationProgress
            }
        }

        // Index personal memories
        if settings.spotlightIndexPersonalMemory {
            let profiles = contextService.loadProfiles()
            for profile in profiles {
                let userId = profile.id.uuidString
                if let memory = contextService.loadUserMemory(userId: userId), !memory.isEmpty {
                    let identifier = "user-\(userId)"
                    let uniqueId = Self.memoryPrefix + identifier
                    let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
                    attributeSet.title = "\(profile.name)의 개인 메모리"
                    attributeSet.contentDescription = String(memory.prefix(Self.maxDescriptionLength))
                    attributeSet.domainIdentifier = Self.domainIdentifier
                    attributeSet.thumbnailData = appIconData()
                    attributeSet.contentURL = URL(string: "dochi://memory/user/\(userId)")
                    attributeSet.contentModificationDate = Date()

                    let item = CSSearchableItem(
                        uniqueIdentifier: uniqueId,
                        domainIdentifier: Self.domainIdentifier,
                        attributeSet: attributeSet
                    )
                    items.append(item)
                }
            }
        }

        rebuildProgress = 0.7

        // Index workspace memories
        let wsId = sessionContext.workspaceId
        if settings.spotlightIndexWorkspaceMemory {
            if let wsMem = contextService.loadWorkspaceMemory(workspaceId: wsId), !wsMem.isEmpty {
                let identifier = "workspace-\(wsId.uuidString)"
                let uniqueId = Self.memoryPrefix + identifier
                let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
                attributeSet.title = "워크스페이스 메모리"
                attributeSet.contentDescription = String(wsMem.prefix(Self.maxDescriptionLength))
                attributeSet.domainIdentifier = Self.domainIdentifier
                attributeSet.thumbnailData = appIconData()
                attributeSet.contentURL = URL(string: "dochi://memory/workspace/\(wsId.uuidString)")
                attributeSet.contentModificationDate = Date()

                let item = CSSearchableItem(
                    uniqueIdentifier: uniqueId,
                    domainIdentifier: Self.domainIdentifier,
                    attributeSet: attributeSet
                )
                items.append(item)
            }
        }

        rebuildProgress = 0.8

        // Index agent memories
        if settings.spotlightIndexAgentMemory {
            let agents = contextService.listAgents(workspaceId: wsId)
            for agentName in agents {
                if let agentMem = contextService.loadAgentMemory(workspaceId: wsId, agentName: agentName), !agentMem.isEmpty {
                    let identifier = "agent-\(wsId.uuidString)-\(agentName)"
                    let uniqueId = Self.memoryPrefix + identifier
                    let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
                    attributeSet.title = "\(agentName) 에이전트 메모리"
                    attributeSet.contentDescription = String(agentMem.prefix(Self.maxDescriptionLength))
                    attributeSet.domainIdentifier = Self.domainIdentifier
                    attributeSet.thumbnailData = appIconData()
                    attributeSet.contentURL = URL(string: "dochi://memory/agent/\(wsId.uuidString)/\(agentName)")
                    attributeSet.contentModificationDate = Date()

                    let item = CSSearchableItem(
                        uniqueIdentifier: uniqueId,
                        domainIdentifier: Self.domainIdentifier,
                        attributeSet: attributeSet
                    )
                    items.append(item)
                }
            }
        }

        rebuildProgress = 0.9

        // Batch-index all items
        if !items.isEmpty {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                searchableIndex.indexSearchableItems(items) { error in
                    if let error {
                        Log.app.error("Spotlight: 배치 인덱싱 실패 — \(error.localizedDescription)")
                    }
                    continuation.resume()
                }
            }
        }

        indexedItemCount = items.count
        rebuildProgress = 1.0
        lastIndexedAt = Date()
        isRebuilding = false

        Log.app.info("Spotlight: 전체 인덱스 재구축 완료 (\(items.count)건)")
    }

    func clearAllIndices() async {
        await clearAllIndicesInternal()
        indexedItemCount = 0
        lastIndexedAt = nil
        Log.app.info("Spotlight: 전체 인덱스 삭제 완료")
    }

    // MARK: - Helpers

    private func clearAllIndicesInternal() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            searchableIndex.deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier]) { error in
                if let error {
                    Log.app.error("Spotlight: 인덱스 삭제 실패 — \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }

    private func conversationDescription(_ conversation: Conversation) -> String {
        // Build summary from first few user messages
        let userMessages = conversation.messages
            .filter { $0.role == .user }
            .prefix(3)
            .map(\.content)
            .joined(separator: " ")

        if userMessages.isEmpty {
            return conversation.summary ?? conversation.title
        }
        return String(userMessages.prefix(Self.maxDescriptionLength))
    }

    private func appIconData() -> Data? {
        NSApp.applicationIconImage?.tiffRepresentation
    }

    // MARK: - Deep Link Parsing

    /// dochi:// URL을 파싱하여 DeepLink 열거형으로 반환
    static func parseDeepLink(url: URL) -> DeepLink? {
        guard url.scheme == "dochi" else { return nil }
        let host = url.host()
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "conversation":
            guard let uuidStr = pathComponents.first, let uuid = UUID(uuidString: uuidStr) else { return nil }
            return .conversation(id: uuid)
        case "memory":
            guard let scope = pathComponents.first else { return nil }
            switch scope {
            case "user":
                guard pathComponents.count >= 2 else { return nil }
                return .memoryUser(userId: pathComponents[1])
            case "agent":
                guard pathComponents.count >= 3 else { return nil }
                return .memoryAgent(workspaceId: pathComponents[1], agentName: pathComponents[2])
            case "workspace":
                guard pathComponents.count >= 2 else { return nil }
                return .memoryWorkspace(workspaceId: pathComponents[1])
            default:
                return nil
            }
        default:
            return nil
        }
    }

    /// 딥링크 대상 열거형
    enum DeepLink: Equatable {
        case conversation(id: UUID)
        case memoryUser(userId: String)
        case memoryAgent(workspaceId: String, agentName: String)
        case memoryWorkspace(workspaceId: String)
    }
}
