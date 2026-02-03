import Foundation
@testable import Dochi

final class MockContextService: ContextServiceProtocol {
    var systemContent: String = ""
    var memoryContent: String = ""
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

    func migrateIfNeeded() {
        migrateIfNeededCalled = true
    }
}
