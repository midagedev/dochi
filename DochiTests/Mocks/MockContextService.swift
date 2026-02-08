import Foundation
@testable import Dochi

final class MockContextService: ContextServiceProtocol {
    var systemContent: String = ""
    var memoryContent: String = ""
    var familyMemoryContent: String = ""
    var userMemories: [UUID: String] = [:]
    var profiles: [UserProfile] = []
    var migrateIfNeededCalled = false

    func loadSystem() -> String {
        systemContent
    }

    func saveSystem(_ content: String) {
        systemContent = content
    }

    var systemPath: String {
        "/mock/system.md"
    }

    func loadMemory() -> String {
        memoryContent
    }

    func saveMemory(_ content: String) {
        memoryContent = content
    }

    func appendMemory(_ content: String) {
        if !memoryContent.isEmpty && !memoryContent.hasSuffix("\n") {
            memoryContent += "\n"
        }
        memoryContent += content
    }

    var memoryPath: String {
        "/mock/memory.md"
    }

    var memorySize: Int {
        memoryContent.utf8.count
    }

    // MARK: - Family Memory

    func loadFamilyMemory() -> String {
        familyMemoryContent
    }

    func saveFamilyMemory(_ content: String) {
        familyMemoryContent = content
    }

    func appendFamilyMemory(_ content: String) {
        if !familyMemoryContent.isEmpty && !familyMemoryContent.hasSuffix("\n") {
            familyMemoryContent += "\n"
        }
        familyMemoryContent += content
    }

    // MARK: - User Memory

    func loadUserMemory(userId: UUID) -> String {
        userMemories[userId] ?? ""
    }

    func saveUserMemory(userId: UUID, content: String) {
        userMemories[userId] = content
    }

    func appendUserMemory(userId: UUID, content: String) {
        var current = userMemories[userId] ?? ""
        if !current.isEmpty && !current.hasSuffix("\n") {
            current += "\n"
        }
        current += content
        userMemories[userId] = current
    }

    // MARK: - Profiles

    func loadProfiles() -> [UserProfile] {
        profiles
    }

    func saveProfiles(_ newProfiles: [UserProfile]) {
        profiles = newProfiles
    }

    func migrateIfNeeded() {
        migrateIfNeededCalled = true
    }
}
