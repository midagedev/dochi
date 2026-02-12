import Foundation
import os

enum Log {
    private static let subsystem = "com.dochi.app"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let llm = Logger(subsystem: subsystem, category: "LLM")
    static let stt = Logger(subsystem: subsystem, category: "STT")
    static let tts = Logger(subsystem: subsystem, category: "TTS")
    static let mcp = Logger(subsystem: subsystem, category: "MCP")
    static let tool = Logger(subsystem: subsystem, category: "Tool")
    static let storage = Logger(subsystem: subsystem, category: "Storage")
    static let cloud = Logger(subsystem: subsystem, category: "Cloud")
    static let telegram = Logger(subsystem: subsystem, category: "Telegram")
}
